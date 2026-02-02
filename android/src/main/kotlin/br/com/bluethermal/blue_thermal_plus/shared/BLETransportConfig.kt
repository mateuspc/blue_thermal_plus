package br.com.bluethermal.blue_thermal_plus.shared
import java.util.UUID

data class BLETransportConfig(
    val serviceUUID: UUID,
    val writeCharUUID: UUID,
    val chunkSize: Int,
    val chunkDelayMs: Long // Android usa milissegundos (Thread.sleep)
) {
    companion object {
        val zebraDefault = BLETransportConfig(
            serviceUUID = UUID.fromString("38EB4A80-C570-11E3-9507-0002A5D5C51B"),
            writeCharUUID = UUID.fromString("38EB4A82-C570-11E3-9507-0002A5D5C51B"),
            chunkSize = 100,
            chunkDelayMs = 10L // 10ms equivale a 10.000us do iOS
        )
    }
}