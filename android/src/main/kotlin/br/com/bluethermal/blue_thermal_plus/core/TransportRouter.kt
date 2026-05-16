package br.com.bluethermal.blue_thermal_plus.core

import br.com.bluethermal.blue_thermal_plus.core.PrinterTransportManager
import br.com.bluethermal.blue_thermal_plus.transports.ble.BleTransport
import br.com.bluethermal.blue_thermal_plus.transports.classic.ClassicTransport
import br.com.bluethermal.blue_thermal_plus.transports.unsupported.UnsupportedTransport

// Certifique-se de ter criado o Enum TransportType conforme passo anterior
import br.com.bluethermal.blue_thermal_plus.core.TransportType

class TransportRouter(
    private val ble: BleTransport,
    private val classic: ClassicTransport,
    private val epson: UnsupportedTransport
) {

    /**
     * ✅ CORREÇÃO: Aceita String? (nullable) para evitar o erro "type mismatch".
     * O safeValueOf trata o nulo retornando BLE por padrão.
     */
    fun manager(transportString: String?): PrinterTransportManager {
        val type = TransportType.safeValueOf(transportString)

        return when (type) {
            TransportType.BLE -> ble
            TransportType.CLASSIC -> classic
            TransportType.EPSON -> epson
        }
    }
}
