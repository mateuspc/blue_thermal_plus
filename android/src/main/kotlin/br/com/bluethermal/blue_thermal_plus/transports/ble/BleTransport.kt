package br.com.bluethermal.blue_thermal_plus.transports.ble

import android.annotation.SuppressLint
import android.bluetooth.*
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanResult
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import br.com.bluethermal.blue_thermal_plus.core.PrinterTransportManager
import br.com.bluethermal.blue_thermal_plus.shared.DeviceStore
import br.com.bluethermal.blue_thermal_plus.shared.EventEmitter
import java.util.*
import kotlin.math.min

@SuppressLint("MissingPermission")
class BleTransport(
    private val context: Context,
    private val adapter: BluetoothAdapter?,
    private val store: DeviceStore
) : PrinterTransportManager {

    private val emitter = EventEmitter()
    override var onEvent: ((Map<String, Any>) -> Unit)?
        get() = emitter.sink
        set(value) { emitter.sink = value }

    // MARK: - Configuration Defaults
    private var serviceUuid: UUID = UUID.fromString("38EB4A80-C570-11E3-9507-0002A5D5C51B")
    private var writeCharUuid: UUID = UUID.fromString("38EB4A82-C570-11E3-9507-0002A5D5C51B")

    // Começamos com 20, que é o seguro. Se o MTU aumentar, nós aumentamos isso.
    private var chunkSize = 20
    private var chunkDelayMs = 15L
    private var autoDisconnectMs = 3000L

    private var bluetoothGatt: BluetoothGatt? = null
    private var writeCharacteristic: BluetoothGattCharacteristic? = null
    private var isScanning = false

    private val mainHandler = Handler(Looper.getMainLooper())

    fun applyConfig(config: Map<String, Any>?) {
        if (config == null) return
        val sUuid = config["serviceUuid"] as? String
        val wUuid = config["writeCharacteristicUuid"] as? String

        if (!sUuid.isNullOrEmpty()) this.serviceUuid = UUID.fromString(sUuid)
        if (!wUuid.isNullOrEmpty()) this.writeCharUuid = UUID.fromString(wUuid)

        // Se o usuário forçar um chunk size no Flutter, usamos ele.
        // Se não, deixamos dinâmico baseado no MTU.
        (config["chunkSize"] as? Int)?.let { this.chunkSize = if (it > 0) it else 20 }
        (config["chunkDelayMs"] as? Int)?.let { this.chunkDelayMs = it.toLong() }
        (config["autoDisconnectMs"] as? Int)?.let { this.autoDisconnectMs = it.toLong() }

        emitter.emit("status", "BLE: Config aplicada. ChunkSize inicial: $chunkSize")
    }

    private val scanCallback = object : ScanCallback() {
        override fun onScanResult(callbackType: Int, result: ScanResult?) {
            result?.device?.let { device ->
                if (store.getBle(device.address) == null) {
                    store.upsertBle(device)
                    val name = device.name ?: "Sem Nome"
                    emitter.emit("deviceFound", device = mapOf("id" to device.address, "name" to name))
                }
            }
        }
        override fun onScanFailed(errorCode: Int) {
            emitter.emit("error", "BLE: Scan falhou ($errorCode)")
        }
    }

    override fun startScan() {
        if (adapter == null || !adapter.isEnabled) {
            emitter.emit("error", "BLE: Bluetooth desligado")
            return
        }
        store.clearBle()
        isScanning = true
        emitter.emit("scanStarted", "BLE: iniciando scan...")
        try {
            adapter.bluetoothLeScanner?.startScan(scanCallback)
        } catch (e: Exception) {
            emitter.emit("error", "BLE: Erro scan: ${e.message}")
        }
    }

    override fun stopScan() {
        if (isScanning && adapter?.isEnabled == true) {
            try { adapter.bluetoothLeScanner?.stopScan(scanCallback) } catch (e: Exception) {}
            isScanning = false
            emitter.emit("scanStopped", "BLE: scan parado")
        }
    }

    // MARK: - Connection
    override fun connect(deviceId: String) {
        stopScan()
        val device = store.getBle(deviceId) ?: try {
            adapter?.getRemoteDevice(deviceId)
        } catch (e: Exception) { null }

        if (device == null) {
            emitter.emit("error", "BLE: Device não encontrado")
            return
        }

        emitter.emit("status", "BLE: conectando a ${device.name}...")

        if (device.bondState == BluetoothDevice.BOND_NONE) {
            device.createBond()
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            bluetoothGatt = device.connectGatt(context, false, gattCallback, BluetoothDevice.TRANSPORT_LE)
        } else {
            bluetoothGatt = device.connectGatt(context, false, gattCallback)
        }
    }

    override fun disconnect() {
        bluetoothGatt?.disconnect()
        bluetoothGatt?.close()
        bluetoothGatt = null
        writeCharacteristic = null
        emitter.emit("disconnected", "BLE: desconectado")
    }

    override fun printRaw(data: ByteArray) {
        if (bluetoothGatt == null || writeCharacteristic == null) {
            emitter.emit("error", "BLE: não pronto (sem serviço/caract)")
            return
        }

        emitter.emit("status", "BLE: enviando dados (Chunk: $chunkSize)...")

        Thread {
            var offset = 0
            while (offset < data.size) {
                // Usa o chunkSize atual (pode ter sido atualizado pelo MTU)
                val length = min(chunkSize, data.size - offset)
                val chunk = Arrays.copyOfRange(data, offset, offset + length)

                writeCharacteristic?.value = chunk

                val props = writeCharacteristic?.properties ?: 0
                // Força Write No Response se disponível (mais rápido para impressoras)
                if ((props and BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE) != 0) {
                    writeCharacteristic?.writeType = BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE
                } else {
                    writeCharacteristic?.writeType = BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
                }

                val success = bluetoothGatt?.writeCharacteristic(writeCharacteristic) ?: false
                if (!success) {
                    // Retry simples
                    Thread.sleep(50)
                    val retry = bluetoothGatt?.writeCharacteristic(writeCharacteristic) ?: false
                    if (!retry) {
                        emitter.emit("error", "BLE: Falha escrita offset $offset")
                        break
                    }
                }
                offset += length
                if (chunkDelayMs > 0) Thread.sleep(chunkDelayMs)
            }
            emitter.emit("status", "✅ BLE enviado! Fechando em ${autoDisconnectMs}ms")
            mainHandler.postDelayed({ disconnect() }, autoDisconnectMs)
        }.start()
    }

    private val gattCallback = object : BluetoothGattCallback() {
        override fun onConnectionStateChange(gatt: BluetoothGatt?, status: Int, newState: Int) {
            if (newState == BluetoothProfile.STATE_CONNECTED) {
                emitter.emit("connected", device = mapOf("id" to (gatt?.device?.address ?: ""), "name" to (gatt?.device?.name ?: "")))

                // ✅ PEDIR AUMENTO DE MTU
                // Isso permite enviar pacotes maiores que 20 bytes (até 512).
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                    emitter.emit("status", "BLE: Solicitando MTU 512...")
                    gatt?.requestMtu(512)
                } else {
                    // Android antigo não suporta MTU alto, inicia serviços direto
                    startServiceDiscovery(gatt)
                }

            } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                emitter.emit("disconnected", "BLE: conexão perdida (status=$status)")
                bluetoothGatt?.close()
                bluetoothGatt = null
            }
        }

        // ✅ Callback quando o MTU muda
        override fun onMtuChanged(gatt: BluetoothGatt?, mtu: Int, status: Int) {
            if (status == BluetoothGatt.GATT_SUCCESS) {
                // O MTU útil é (Total - 3 bytes de cabeçalho).
                // Ex: Se MTU = 512, Payload = 509.
                // Atualizamos o chunkSize para ser mais eficiente.
                chunkSize = mtu - 3
                emitter.emit("status", "BLE: MTU negociado: $mtu. Novo ChunkSize: $chunkSize")
            } else {
                emitter.emit("status", "BLE: Falha ao negociar MTU. Mantendo 20 bytes.")
                chunkSize = 20
            }

            // Depois do MTU, descobrimos os serviços
            startServiceDiscovery(gatt)
        }

        private fun startServiceDiscovery(gatt: BluetoothGatt?) {
            // Pequeno delay para estabilidade
            mainHandler.postDelayed({
                emitter.emit("status", "BLE: Buscando serviços...")
                gatt?.discoverServices()
            }, 500)
        }

        override fun onServicesDiscovered(gatt: BluetoothGatt?, status: Int) {
            if (status == BluetoothGatt.GATT_SUCCESS) {
                val service = gatt?.getService(serviceUuid)
                if (service == null) {
                    emitter.emit("status", "BLE: Serviço alvo não encontrado.")
                    return
                }

                val characteristic = service.getCharacteristic(writeCharUuid)
                if (characteristic == null) {
                    emitter.emit("status", "BLE: Característica não encontrada.")
                    return
                }

                writeCharacteristic = characteristic
                emitter.emit("ready", "BLE: Pronto (MTU=${chunkSize})")
            } else {
                emitter.emit("error", "BLE: Erro discoverServices status=$status")
            }
        }
    }
}