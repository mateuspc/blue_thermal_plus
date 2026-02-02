package br.com.bluethermal.blue_thermal_plus.transports.classic

import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothSocket
import android.os.Handler
import android.os.Looper
import br.com.bluethermal.blue_thermal_plus.core.PrinterTransportManager
import br.com.bluethermal.blue_thermal_plus.shared.DeviceStore
import br.com.bluethermal.blue_thermal_plus.shared.EventEmitter
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.util.UUID

@SuppressLint("MissingPermission")
class ClassicTransport(
    private val adapter: BluetoothAdapter?,
    private val store: DeviceStore
) : PrinterTransportManager {

    private val emitter = EventEmitter()
    override var onEvent: ((Map<String, Any>) -> Unit)?
        get() = emitter.sink
        set(value) { emitter.sink = value }

    // UUID Padrão para SPP (Serial Port Profile) - Universal para impressoras térmicas
    private val SPP_UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")

    private var socket: BluetoothSocket? = null
    private var outputStream: OutputStream? = null
    private var inputStream: InputStream? = null

    // Thread para leitura de dados (equivalente ao StreamDelegate do iOS)
    private var readThread: Thread? = null
    private var isReading = false

    // Configurações
    private var autoDisconnectMs = 3000L

    // ✅ Configurações vindas do Flutter
    // preferredProtocol é ignorado no Android (sempre usa SPP UUID),
    // mas mantemos a assinatura para compatibilidade.
    fun applyConfig(config: Map<String, Any>?) {
        if (config == null) return

        // preferredProtocol -> Ignorado no Android (Usa SPP)
        val preferredProtocol = config["preferredProtocol"] as? String

        // autoDisconnectMs
        (config["autoDisconnectMs"] as? Int)?.let {
            this.autoDisconnectMs = it.toLong()
        }

        emitter.emit(
            type = "status",
            message = "Classic: config aplicado protocol=${preferredProtocol ?: "SPP(Default)"} autoDiscMs=$autoDisconnectMs"
        )
    }

    override fun startScan() {
        if (adapter == null) {
            emitter.emit("error", "Bluetooth não disponível")
            return
        }
        store.clearClassic()

        emitter.emit("scanStarted", "Classic: listando dispositivos pareados...")

        // No Android Classic, listamos os dispositivos PAREADOS (Bonded)
        val bonded = adapter.bondedDevices
        if (!bonded.isNullOrEmpty()) {
            for (device in bonded) {
                store.upsertClassic(device)
                emitter.emit(
                    type = "deviceFound",
                    device = mapOf("id" to device.address, "name" to (device.name ?: "Sem Nome")),
                    // Android não expõe protocolStrings nativamente como iOS
                    extra = mapOf("protocols" to emptyList<String>())
                )
            }
        }

        emitter.emit("scanStopped", "Classic: lista pronta")
    }

    override fun stopScan() {
        // No Android, cancelar discovery economiza bateria, embora aqui estejamos listando pareados.
        if (adapter?.isDiscovering == true) {
            adapter.cancelDiscovery()
        }
        emitter.emit("scanStopped", "Classic: stopScan (noop)")
    }

    override fun connect(deviceId: String) {
        // ✅ evita trabalho/efeitos colaterais se ainda não estava conectado
        if (socket != null && socket!!.isConnected) {
            disconnect()
        }

        val device = store.getClassic(deviceId) ?: adapter?.getRemoteDevice(deviceId)
        if (device == null) {
            emitter.emit("error", "Classic: dispositivo não encontrado: $deviceId")
            return
        }

        Thread {
            try {
                emitter.emit("status", "Classic: criando socket SPP para ${device.name}...")

                // Criação do Socket SPP
                val tempSocket = device.createRfcommSocketToServiceRecord(SPP_UUID)

                // Conecta (Bloqueante)
                tempSocket.connect()

                socket = tempSocket
                outputStream = tempSocket.outputStream
                inputStream = tempSocket.inputStream

                emitter.emit("connected", device = mapOf("id" to device.address, "name" to (device.name ?: "")))

                // Como streams abrem imediatamente no Android, emitimos Ready
                emitter.emit("ready", "Classic: Socket aberto e pronto")

                // Inicia loop de leitura (Equivalente ao StreamDelegate hasBytesAvailable)
                startReading()

            } catch (e: IOException) {
                emitter.emit("error", "Classic: Erro de conexão: ${e.message}")
                try { socket?.close() } catch (ignored: Exception) {}
            }
        }.start()
    }

    override fun disconnect() {
        isReading = false // Para a thread de leitura
        try {
            outputStream?.close()
            inputStream?.close()
            socket?.close()
        } catch (e: Exception) {
            // Ignora erros no fechamento
        }

        outputStream = null
        inputStream = null
        socket = null

        emitter.emit("disconnected", "Classic: desconectado")
    }

    override fun printRaw(data: ByteArray) {
        if (outputStream == null) {
            emitter.emit("error", "Classic: não conectado")
            return
        }

        Thread {
            try {
                emitter.emit("status", "Classic: enviando dados...")
                outputStream?.write(data)
                outputStream?.flush()

                emitter.emit("status", "📤 Classic: enviado ${data.size} bytes (auto-disconnect ${autoDisconnectMs}ms)")

                // Auto disconnect
                Handler(Looper.getMainLooper()).postDelayed({
                    disconnect()
                }, autoDisconnectMs)

            } catch (e: IOException) {
                emitter.emit("error", "Classic: erro de escrita: ${e.message}")
                disconnect()
            }
        }.start()
    }

    // MARK: - Leitura (Simulando StreamDelegate)
    private fun startReading() {
        isReading = true
        val stream = inputStream ?: return

        // Thread dedicada para ler respostas da impressora
        readThread = Thread {
            val buffer = ByteArray(1024)
            while (isReading) {
                try {
                    if (stream.available() > 0) {
                        val bytesRead = stream.read(buffer)
                        if (bytesRead > 0) {
                            val readData = buffer.copyOf(bytesRead)
                            val text = String(readData, Charsets.US_ASCII)
                                .replace("\r", "")
                                .replace("\n", "")

                            // Se for texto legível, loga o texto, senão avisa que é binário
                            if (text.isNotEmpty() && text.all { !it.isISOControl() || it.isWhitespace() }) {
                                emitter.emit("status", "📥 Classic: recv [$text]")
                            } else {
                                emitter.emit("status", "📥 Classic: recv (binário)")
                            }
                        }
                    } else {
                        // Evita loop infinito com 100% de CPU se não tiver dados
                        Thread.sleep(100)
                    }
                } catch (e: IOException) {
                    if (isReading) {
                        emitter.emit("error", "Classic: erro de leitura: ${e.message}")
                        disconnect()
                    }
                    break
                }
            }
        }
        readThread?.start()
    }
}