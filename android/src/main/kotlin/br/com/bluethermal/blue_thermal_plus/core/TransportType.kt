package br.com.bluethermal.blue_thermal_plus.core

import java.util.Locale

enum class TransportType {
    BLE,
    CLASSIC,
    EPSON;

    companion object {
        // Converte a String do Flutter ("ble", "classic") para o Enum.
        // Se vier null ou algo desconhecido, retorna BLE como padrão.
        fun safeValueOf(value: String?): TransportType {
            if (value == null) return BLE

            return when (value.lowercase(Locale.US)) {
                "classic" -> CLASSIC
                "epson" -> EPSON
                "ble" -> BLE
                else -> BLE // Fallback seguro
            }
        }
    }
}
