package br.com.bluethermal.blue_thermal_plus.transports.classic

import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
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

    // UUID Padrão para SPP (Serial Port Profile)
    private val SPP_UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")

    private var socket: BluetoothSocket? = null
    private var outputStream: OutputStream? = null
    private var inputStream: InputStream? = null

    // Thread para leitura
    private var readThread: Thread? = null
    @Volatile private var isReading = false

    // Thread para impressão (evita prints concorrentes)
    @Volatile private var isPrinting = false

    // Configurações (defaults seguros p/ impressão grande)
    private var autoDisconnectMs = 15000L   // ✅ maior por padrão
    private var chunkSize = 512             // ✅ chunk no classic
    private var chunkDelayMs = 10L          // ✅ pequeno delay para buffer

    // handler/disconnect
    private val mainHandler = Handler(Looper.getMainLooper())
    private var disconnectRunnable: Runnable? = null

    // ✅ Configurações vindas do Flutter
    fun applyConfig(config: Map<String, Any>?) {
        if (config == null) return

        val preferredProtocol = config["preferredProtocol"] as? String

        (config["autoDisconnectMs"] as? Int)?.let { this.autoDisconnectMs = it.toLong() }
        (config["chunkSize"] as? Int)?.let { if (it > 0) this.chunkSize = it }
        (config["chunkDelayMs"] as? Int)?.let { this.chunkDelayMs = it.toLong() }

        emitter.emit(
            type = "status",
            message = "Classic: config aplicado protocol=${preferredProtocol ?: "SPP(Default)"} " +
                    "autoDiscMs=$autoDisconnectMs chunkSize=$chunkSize chunkDelayMs=$chunkDelayMs"
        )
    }

    override fun startScan() {
        if (adapter == null) {
            emitter.emit("error", "Bluetooth não disponível")
            return
        }

        store.clearClassic()
        emitter.emit("scanStarted", "Classic: listando dispositivos pareados...")

        val bonded = adapter.bondedDevices
        if (!bonded.isNullOrEmpty()) {
            for (device in bonded) {
                store.upsertClassic(device)
                emitter.emit(
                    type = "deviceFound",
                    device = mapOf("id" to device.address, "name" to (device.name ?: "Sem Nome")),
                    extra = mapOf("protocols" to emptyList<String>())
                )
            }
        }

        emitter.emit("scanStopped", "Classic: lista pronta")
    }

    override fun stopScan() {
        if (adapter?.isDiscovering == true) {
            try { adapter.cancelDiscovery() } catch (_: Exception) {}
        }
        emitter.emit("scanStopped", "Classic: stopScan (noop)")
    }

    override fun connect(deviceId: String) {
        // se já conectado, desconecta
        if (socket != null && socket!!.isConnected) {
            disconnect()
        }

        val device = store.getClassic(deviceId) ?: try {
            adapter?.getRemoteDevice(deviceId)
        } catch (_: Exception) { null }

        if (device == null) {
            emitter.emit("error", "Classic: dispositivo não encontrado: $deviceId")
            return
        }

        Thread {
            try {
                emitter.emit("status", "Classic: criando socket SPP para ${device.name}...")

                // ✅ Importante para RFCOMM: cancelDiscovery antes de conectar
                try { adapter?.cancelDiscovery() } catch (_: Exception) {}

                val tempSocket = device.createRfcommSocketToServiceRecord(SPP_UUID)

                // Conecta (bloqueante)
                tempSocket.connect()

                socket = tempSocket
                outputStream = tempSocket.outputStream
                inputStream = tempSocket.inputStream

                // ✅ cancela qualquer auto-disconnect pendente
                cancelAutoDisconnect()

                emitter.emit(
                    "connected",
                    device = mapOf("id" to device.address, "name" to (device.name ?: ""))
                )
                emitter.emit("ready", "Classic: Socket aberto e pronto")

                startReading()
            } catch (e: IOException) {
                emitter.emit("error", "Classic: Erro de conexão: ${e.message}")
                safeClose()
            } catch (e: Exception) {
                emitter.emit("error", "Classic: Erro inesperado: ${e.message}")
                safeClose()
            }
        }.start()
    }

    override fun disconnect() {
        isReading = false
        cancelAutoDisconnect()
        safeClose()
        emitter.emit("disconnected", "Classic: desconectado")
    }

    override fun printRaw(data: ByteArray) {
        val out = outputStream
        if (out == null) {
            emitter.emit("error", "Classic: não conectado")
            return
        }

        // ✅ evita print concorrente
        if (isPrinting) {
            emitter.emit("status", "Classic: print ignorado (já existe impressão em andamento)")
            return
        }

        isPrinting = true

        Thread {
            try {
                cancelAutoDisconnect()

                emitter.emit(
                    "status",
                    "Classic: enviando dados... (${data.size} bytes, chunk=$chunkSize, delay=${chunkDelayMs}ms)"
                )

                var offset = 0
                while (offset < data.size) {
                    val end = minOf(offset + chunkSize, data.size)
                    out.write(data, offset, end - offset)
                    out.flush()
                    offset = end

                    if (chunkDelayMs > 0) Thread.sleep(chunkDelayMs)
                }

                emitter.emit("status", "📤 Classic: enviado ${data.size} bytes")

                // ✅ Auto-disconnect: só se > 0 (0 = não desconecta)
                if (autoDisconnectMs > 0) {
                    scheduleAutoDisconnect()
                    emitter.emit("status", "Classic: aguardando ${autoDisconnectMs}ms para auto-disconnect")
                } else {
                    emitter.emit("status", "Classic: autoDisconnect desativado (autoDisconnectMs=0)")
                }

            } catch (e: IOException) {
                emitter.emit("error", "Classic: erro de escrita: ${e.message}")
                disconnect()
            } catch (e: Exception) {
                emitter.emit("error", "Classic: erro inesperado na escrita: ${e.message}")
                disconnect()
            } finally {
                isPrinting = false
            }
        }.start()
    }

    // MARK: - Leitura
    private fun startReading() {
        isReading = true
        val stream = inputStream ?: return

        readThread = Thread {
            val buffer = ByteArray(1024)
            while (isReading) {
                try {
                    val available = try {
                        stream.available()
                    } catch (_: Exception) {
                        0
                    }
                    if (available > 0) {
                        val bytesRead = stream.read(buffer)
                        if (bytesRead > 0) {
                            val readData = buffer.copyOf(bytesRead)
                            val text = String(readData, Charsets.US_ASCII)
                                .replace("\r", "")
                                .replace("\n", "")

                            if (text.isNotEmpty() && text.all { !it.isISOControl() || it.isWhitespace() }) {
                                emitter.emit("status", "📥 Classic: recv [$text]")
                            } else {
                                emitter.emit(
                                    "status",
                                    "📥 Classic: recv (binário ${bytesRead} bytes)"
                                )
                            }
                        }
                    } else {
                        Thread.sleep(100)
                    }
                } catch (e: IOException) {
                    if (isReading) {
                        emitter.emit("error", "Classic: erro de leitura: ${e.message}")
                        disconnect()
                    }
                    break
                } catch (_: Exception) {
                    // evita crash por qualquer bug de stream
                    Thread.sleep(100)
                }
            }
        }
        readThread?.start()
    }

    private fun scheduleAutoDisconnect() {
        cancelAutoDisconnect()
        disconnectRunnable = Runnable { disconnect() }
        mainHandler.postDelayed(disconnectRunnable!!, autoDisconnectMs)
    }

    private fun cancelAutoDisconnect() {
        disconnectRunnable?.let { mainHandler.removeCallbacks(it) }
        disconnectRunnable = null
    }

    private fun safeClose() {
        try { outputStream?.close() } catch (_: Exception) {}
        try { inputStream?.close() } catch (_: Exception) {}
        try { socket?.close() } catch (_: Exception) {}

        outputStream = null
        inputStream = null
        socket = null
    }
}
