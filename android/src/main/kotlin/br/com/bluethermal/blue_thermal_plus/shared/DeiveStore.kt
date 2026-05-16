package br.com.bluethermal.blue_thermal_plus.shared

import android.bluetooth.BluetoothDevice

class DeviceStore {

    // MARK: - BLE Storage
    // No Android, a chave única é o MAC Address (String), não UUID gerado pelo iOS.
    private val ble = mutableMapOf<String, BluetoothDevice>()

    fun upsertBle(device: BluetoothDevice) {
        ble[device.address] = device
    }

    fun getBle(address: String): BluetoothDevice? {
        return ble[address]
    }

    fun clearBle() {
        ble.clear()
    }

    /// Snapshot serializável para o Flutter (List<Map>)
    fun snapshotBle(): List<Map<String, Any>> {
        // Ordena alfabeticamente pelo nome (case insensitive simulado)
        val sortedDevices = ble.values.sortedBy { (it.name ?: "").lowercase() }

        return sortedDevices.map { device ->
            mapOf(
                "id" to device.address,
                "name" to (device.name ?: "Dispositivo Sem Nome")
            )
        }
    }

    // MARK: - Classic Storage
    // No Android, Classic também é BluetoothDevice (não existe EAAccessory separado)
    private val classic = mutableMapOf<String, BluetoothDevice>()

    fun upsertClassic(device: BluetoothDevice) {
        classic[device.address] = device
    }

    // ✅ CORREÇÃO: Renomeado de 'classicAccessory' para 'getClassic'
    fun getClassic(address: String): BluetoothDevice? {
        return classic[address]
    }

    fun clearClassic() {
        classic.clear()
    }

    /// Snapshot serializável para o Flutter (List<Map>)
    fun snapshotClassic(): List<Map<String, Any>> {
        val sortedDevices = classic.values.sortedBy { (it.name ?: "").lowercase() }

        return sortedDevices.map { device ->
            mapOf(
                "id" to device.address,
                "name" to (device.name ?: "Dispositivo Sem Nome"),
                // Android não lista "protocol strings" (MFi) nativamente no scan.
                // Enviamos lista vazia para manter consistência de tipo com o iOS.
                "protocols" to emptyList<String>()
            )
        }
    }

    // Helper para o Plugin decidir qual lista retornar
    fun snapshot(transport: String): List<Map<String, Any>> {
        return when (transport) {
            "classic" -> snapshotClassic()
            "epson" -> emptyList()
            else -> snapshotBle()
        }
    }
}
