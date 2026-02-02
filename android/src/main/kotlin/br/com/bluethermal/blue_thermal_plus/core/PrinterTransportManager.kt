package br.com.bluethermal.blue_thermal_plus.core

interface PrinterTransportManager {
    var onEvent: ((Map<String, Any>) -> Unit)?

    fun startScan()
    fun stopScan()
    fun connect(deviceId: String)
    fun disconnect()
    fun printRaw(data: ByteArray)
}