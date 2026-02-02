import Flutter
import UIKit

public final class BlueThermalPlusPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {

  private var eventSink: FlutterEventSink?
  private let store = DeviceStore()
  private lazy var ble = ZebraBLETransport(store: store)
  private lazy var classic = EAClassicTransport(store: store)
  private lazy var router = TransportRouter(ble: ble, classic: classic)
  private var bleConfig: [String: Any] = [:]
  private var classicConfig: [String: Any] = [:]

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = BlueThermalPlusPlugin()

    let method = FlutterMethodChannel(
        name: "blue_thermal_plus/methods",
        binaryMessenger: registrar.messenger()
    )
    registrar.addMethodCallDelegate(instance, channel: method)

    let events = FlutterEventChannel(
        name: "blue_thermal_plus/events",
        binaryMessenger: registrar.messenger()
    )
    events.setStreamHandler(instance)
  }

  // MARK: - EventChannel
  public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    self.eventSink = events
    // Redireciona eventos dos transportes para o Flutter
    ble.onEvent = { [weak self] payload in self?.eventSink?(payload) }
    classic.onEvent = { [weak self] payload in self?.eventSink?(payload) }
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    ble.onEvent = nil
    classic.onEvent = nil
    return nil
  }

  // MARK: - MethodChannel
  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]

    // Identifica qual transporte usar (default: ble)
    let transportStr = (args["transport"] as? String) ?? "ble"
    let transport = TransportType(rawValue: transportStr) ?? .ble
    let manager = router.manager(for: transport)

    switch call.method {

        // ✅ CONFIGURE: Salva e aplica as configurações globais
    case "configure":
      if let b = args["ble"] as? [String: Any] {
        bleConfig = b
        applyBleConfigFrom(b)
      }
      if let c = args["classic"] as? [String: Any] {
        classicConfig = c
        applyClassicConfigFrom(c)
      }
      result(nil)

    case "startScan":
      manager.startScan()
      result(nil)

    case "stopScan":
      manager.stopScan()
      result(nil)

        // ✅ CONNECT: A correção principal está aqui
    case "connect":
      guard let deviceId = args["deviceId"] as? String, !deviceId.isEmpty else {
        result(FlutterError(code: "bad_args", message: "deviceId missing", details: nil))
        return
      }

      // 1. Aplica a configuração GLOBAL salva anteriormente (via .configure)
      // Isso garante que UUIDs do ESP32 sejam carregados antes de conectar.
      if transport == .ble {
        applyBleConfigFrom(bleConfig)
      } else {
        applyClassicConfigFrom(classicConfig)
      }

      // 2. Verifica se existe override específico nesta chamada (opcional)
      // Se não houver override, mantemos a config global.
      if transport == .ble {
        if let b = args["ble"] as? [String: Any] {
          applyBleConfigFrom(b)
        }
        // FIX: Removemos o 'else { applyBleConfigFrom(args) }'
        // Isso impedia que argumentos vazios resetassem o driver para Zebra.
      } else {
        if let c = args["classic"] as? [String: Any] {
          applyClassicConfigFrom(c)
        }
      }

      manager.connect(deviceId: deviceId)
      result(nil)

    case "disconnect":
      manager.disconnect()
      result(nil)

    case "printRawBytes":
      guard let typed = args["data"] as? FlutterStandardTypedData else {
        result(FlutterError(code: "bad_args", message: "data missing", details: nil))
        return
      }
      manager.printRaw(data: typed.data)
      result(nil)

    case "getDiscoveredDevices":
      result(store.snapshot(for: transport))

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Helpers: Apply BLE Config
  private func applyBleConfigFrom(_ args: [String: Any]) {
    // Extrai os valores do mapa (podem ser nulos, o Transport lida com defaults se necessário)
    let serviceUuid = args["serviceUuid"] as? String
    let writeCharacteristicUuid = args["writeCharacteristicUuid"] as? String

    let chunkSize = args["chunkSize"] as? Int

    // Dart manda ms, Swift transport usa us (microsegundos) internamente
    let chunkDelayMs = args["chunkDelayMs"] as? Int
    let chunkDelayUs: Int? = chunkDelayMs != nil ? max(0, chunkDelayMs!) * 1000 : nil

    let autoDisconnectMs = args["autoDisconnectMs"] as? Int

    ble.applyBleConfig(
        serviceUuid: serviceUuid,
        writeCharUuid: writeCharacteristicUuid,
        chunkSize: chunkSize,
        chunkDelayUs: chunkDelayUs,
        autoDisconnectMs: autoDisconnectMs
    )
  }

  // MARK: - Helpers: Apply Classic Config
  private func applyClassicConfigFrom(_ args: [String: Any]) {
    let preferredProtocol = args["preferredProtocol"] as? String
    let autoDisconnectMs = args["autoDisconnectMs"] as? Int

    classic.applyClassicConfig(
        preferredProtocol: preferredProtocol,
        autoDisconnectMs: autoDisconnectMs
    )
  }
}