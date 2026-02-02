package br.com.bluethermal.blue_thermal_plus

import android.bluetooth.BluetoothManager
import android.content.Context

// ✅ CORREÇÃO 1: O import correto para NonNull no AndroidX
import androidx.annotation.NonNull

import br.com.bluethermal.blue_thermal_plus.core.TransportRouter
import br.com.bluethermal.blue_thermal_plus.shared.DeviceStore
import br.com.bluethermal.blue_thermal_plus.transports.ble.BleTransport
import br.com.bluethermal.blue_thermal_plus.transports.classic.ClassicTransport

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

class BlueThermalPlusPlugin : FlutterPlugin, MethodCallHandler, EventChannel.StreamHandler {

    private lateinit var channel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private lateinit var context: Context

    private val store = DeviceStore()

    private val bleTransport by lazy {
        val manager = context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
        BleTransport(context, manager.adapter, store)
    }

    private val classicTransport by lazy {
        val manager = context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
        ClassicTransport(manager.adapter, store)
    }

    private val router by lazy {
        TransportRouter(bleTransport, classicTransport)
    }

    private var globalBleConfig: Map<String, Any>? = null
    private var globalClassicConfig: Map<String, Any>? = null

    override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        context = flutterPluginBinding.applicationContext
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "blue_thermal_plus/methods")
        channel.setMethodCallHandler(this)
        eventChannel = EventChannel(flutterPluginBinding.binaryMessenger, "blue_thermal_plus/events")
        eventChannel.setStreamHandler(this)
    }

    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        val sink: (Map<String, Any>) -> Unit = { payload -> events?.success(payload) }
        bleTransport.onEvent = sink
        classicTransport.onEvent = sink
    }

    override fun onCancel(arguments: Any?) {
        bleTransport.onEvent = null
        classicTransport.onEvent = null
    }

    override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
        val args = call.arguments as? Map<String, Any> ?: emptyMap()
        val transportStr = args["transport"] as? String

        // ✅ CORREÇÃO 2: Agora o router.manager aceita String? (nulo),
        // então o erro de Type Mismatch vai sumir.
        val manager = router.manager(transportStr)

        // Mantemos essa flag para a lógica de config
        val isBle = (transportStr == "ble" || transportStr == null)

        when (call.method) {
            "configure" -> {
                val b = args["ble"] as? Map<String, Any>
                if (b != null) {
                    globalBleConfig = b
                    bleTransport.applyConfig(b)
                }
                val c = args["classic"] as? Map<String, Any>
                if (c != null) {
                    globalClassicConfig = c
                    classicTransport.applyConfig(c)
                }
                result.success(null)
            }
            "startScan" -> {
                manager.startScan()
                result.success(null)
            }
            "stopScan" -> {
                manager.stopScan()
                result.success(null)
            }
            "connect" -> {
                val deviceId = args["deviceId"] as? String
                if (deviceId.isNullOrEmpty()) {
                    result.error("bad_args", "deviceId missing", null)
                    return
                }

                // Lógica de aplicar config antes de conectar
                if (isBle) {
                    bleTransport.applyConfig(globalBleConfig)
                } else {
                    classicTransport.applyConfig(globalClassicConfig)
                }

                // Override opcional se vier no connect
                if (isBle) {
                    val b = args["ble"] as? Map<String, Any>
                    if (b != null) bleTransport.applyConfig(b)
                } else {
                    val c = args["classic"] as? Map<String, Any>
                    if (c != null) classicTransport.applyConfig(c)
                }

                manager.connect(deviceId)
                result.success(null)
            }
            "disconnect" -> {
                manager.disconnect()
                result.success(null)
            }
            "printRawBytes" -> {
                val data = args["data"] as? ByteArray
                if (data == null) {
                    result.error("bad_args", "data missing", null)
                    return
                }
                manager.printRaw(data)
                result.success(null)
            }
            "getDiscoveredDevices" -> {
                val safeTransport = transportStr ?: "ble"
                result.success(store.snapshot(safeTransport))
            }
            else -> result.notImplemented()
        }
    }
}