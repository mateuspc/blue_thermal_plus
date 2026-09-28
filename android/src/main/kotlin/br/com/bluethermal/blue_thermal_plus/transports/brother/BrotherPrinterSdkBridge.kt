package br.com.bluethermal.blue_thermal_plus.transports.brother

import android.bluetooth.BluetoothAdapter
import java.lang.reflect.InvocationTargetException

internal data class BrotherSdkResult(
    val ok: Boolean,
    val code: String,
    val message: String,
)

/**
 * Reflection boundary around BrotherPrintLibrary.aar.
 *
 * Reflection keeps the public plugin buildable without redistributing the
 * proprietary SDK. A host app can opt in by providing the AAR at
 * android/Frameworks/BrotherPrintLibrary.aar.
 */
internal class BrotherPrinterSdkBridge(
    private val adapter: BluetoothAdapter?,
) {
    private var driver: Any? = null

    fun connect(deviceAddress: String): BrotherSdkResult {
        if (!isSdkAvailable()) {
            return failure(
                "sdk_missing",
                "Brother Print SDK não encontrado. Adicione BrotherPrintLibrary.aar ao app.",
            )
        }
        val bluetoothAdapter = adapter
            ?: return failure("bluetooth_unavailable", "Bluetooth não disponível.")

        disconnect()

        return runCatching {
            val channelClass = Class.forName("com.brother.sdk.lmprinter.Channel")
            val channel = channelClass
                .getMethod(
                    "newBluetoothChannel",
                    String::class.java,
                    BluetoothAdapter::class.java,
                )
                .invoke(null, deviceAddress, bluetoothAdapter)

            val generatorClass = Class.forName(
                "com.brother.sdk.lmprinter.PrinterDriverGenerator",
            )
            val generateResult = generatorClass
                .getMethod("openChannel", channelClass)
                .invoke(null, channel)
                ?: return@runCatching failure(
                    "driver_missing",
                    "Brother SDK: resultado de abertura ausente.",
                )

            val error = generateResult.javaClass.getMethod("getError").invoke(generateResult)
                ?: return@runCatching failure(
                    "open_channel_error_missing",
                    "Brother SDK: erro de abertura ausente.",
                )
            val errorCode = error.javaClass
                .getMethod("getCode")
                .invoke(error)
                ?.toString()
                ?: "Unknown"
            if (errorCode != "NoError") {
                return@runCatching failure(
                    "open_channel_$errorCode",
                    "Brother SDK: não foi possível abrir o canal ($errorCode).",
                )
            }

            driver = generateResult.javaClass.getMethod("getDriver").invoke(generateResult)
            if (driver == null) {
                failure("driver_missing", "Brother SDK: driver não foi criado.")
            } else {
                success("Brother SDK: conectado")
            }
        }.getOrElse(::reflectionFailure)
    }

    fun disconnect(): BrotherSdkResult {
        val current = driver ?: return success("Brother SDK: já desconectado")
        driver = null
        return runCatching {
            current.javaClass.getMethod("closeChannel").invoke(current)
            success("Brother SDK: desconectado")
        }.getOrElse(::reflectionFailure)
    }

    fun printRaw(data: ByteArray): BrotherSdkResult {
        if (data.isEmpty()) {
            return failure("bad_args", "Dados de impressão Brother ausentes.")
        }
        val current = driver
            ?: return failure("not_connected", "Brother SDK: impressora não conectada.")

        return runCatching {
            val printError = current.javaClass
                .getMethod("sendRawData", ByteArray::class.java)
                .invoke(current, data)
                ?: return@runCatching failure(
                    "print_result_missing",
                    "Brother SDK: resultado de impressão ausente.",
                )
            val errorCode = printError.javaClass
                .getMethod("getCode")
                .invoke(printError)
                ?.toString()
                ?: "Unknown"
            if (errorCode == "NoError") {
                success("Brother SDK: enviado ${data.size} bytes")
            } else {
                val description = printError.javaClass
                    .getMethod("getErrorDescription")
                    .invoke(printError)
                    ?.toString()
                    .orEmpty()
                failure(
                    "print_$errorCode",
                    description.ifEmpty { "Brother SDK: falha ao imprimir ($errorCode)." },
                )
            }
        }.getOrElse(::reflectionFailure)
    }

    private fun reflectionFailure(error: Throwable): BrotherSdkResult {
        val cause = (error as? InvocationTargetException)?.targetException ?: error
        return failure(
            "sdk_exception",
            cause.message ?: "Brother SDK: falha inesperada.",
        )
    }

    private fun success(message: String) = BrotherSdkResult(true, "ok", message)

    private fun failure(code: String, message: String) =
        BrotherSdkResult(false, code, message)

    companion object {
        fun isSdkAvailable(): Boolean = runCatching {
            Class.forName("com.brother.sdk.lmprinter.PrinterDriverGenerator")
            true
        }.getOrDefault(false)
    }
}
