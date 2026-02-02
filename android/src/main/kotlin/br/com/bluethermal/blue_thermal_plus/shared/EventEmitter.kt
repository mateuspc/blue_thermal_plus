package br.com.bluethermal.blue_thermal_plus.shared

import android.os.Handler
import android.os.Looper

class EventEmitter {
    // Equivalente a: var sink: (([String: Any]) -> Void)?
    var sink: ((Map<String, Any>) -> Unit)? = null

    // Necessário no Android para garantir que o evento suba na Main Thread
    private val handler = Handler(Looper.getMainLooper())

    fun emit(
        type: String,
        message: String? = null,
        device: Map<String, Any>? = null,
        extra: Map<String, Any>? = null
    ) {
        // Equivalente a: var payload: [String: Any] = ["type": type]
        val payload = mutableMapOf<String, Any>("type" to type)

        // Equivalente a: if let message { payload["message"] = message }
        if (message != null) {
            payload["message"] = message
        }

        // Equivalente a: if let device { payload["device"] = device }
        if (device != null) {
            payload["device"] = device
        }

        // Equivalente a: if let extra { for (k, v) in extra { payload[k] = v } }
        if (extra != null) {
            payload.putAll(extra)
        }

        // Equivalente a: sink?(payload)
        // Envelopamos no handler.post para evitar crashes de Thread
        handler.post {
            sink?.invoke(payload)
        }
    }
}