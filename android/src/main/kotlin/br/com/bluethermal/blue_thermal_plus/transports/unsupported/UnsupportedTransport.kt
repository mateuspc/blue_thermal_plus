package br.com.bluethermal.blue_thermal_plus.transports.unsupported

import br.com.bluethermal.blue_thermal_plus.core.PrinterTransportManager
import br.com.bluethermal.blue_thermal_plus.shared.EventEmitter

class UnsupportedTransport(
    private val message: String
) : PrinterTransportManager {
    override var onEvent: ((Map<String, Any>) -> Unit)? = null
        set(value) {
            field = value
            emitter.sink = value
        }

    private val emitter = EventEmitter()

    override fun startScan() {
        emitter.emit("scanStarted", message)
        emitter.emit("error", message)
        emitter.emit("scanStopped", message)
    }

    override fun stopScan() {
        emitter.emit("scanStopped", message)
    }

    override fun connect(deviceId: String) {
        emitter.emit("error", message)
    }

    override fun disconnect() {
        emitter.emit("disconnected", message)
    }

    override fun printRaw(data: ByteArray) {
        emitter.emit("error", message)
    }
}
