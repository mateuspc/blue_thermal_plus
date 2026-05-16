import Foundation

final class EpsonEposTransport: NSObject, PrinterTransportManager {

  var onEvent: (([String: Any]) -> Void)? {
    didSet { emitter.sink = onEvent }
  }

  func applyEpsonConfig(
      portType: String?,
      printerSeries: String?,
      modelLang: String?,
      connectTimeoutMs: Int?,
      sendTimeoutMs: Int?,
      autoDisconnectMs: Int?
  ) {
    if let portType, !portType.isEmpty { self.portType = portType }
    if let printerSeries, !printerSeries.isEmpty { self.printerSeries = printerSeries }
    if let modelLang, !modelLang.isEmpty { self.modelLang = modelLang }
    if let connectTimeoutMs { self.connectTimeoutMs = max(0, connectTimeoutMs) }
    if let sendTimeoutMs { self.sendTimeoutMs = max(0, sendTimeoutMs) }
    if let autoDisconnectMs { self.autoDisconnectMs = max(0, autoDisconnectMs) }

    emitter.emit(
        type: "status",
        message: "Epson ePOS: config port=\(self.portType) series=\(self.printerSeries) lang=\(self.modelLang)"
    )
  }

  func startScan() {
    devices.removeAll()
    emitter.emit(type: "scanStarted", message: "Epson ePOS: iniciando discovery...")
    let result = bridgeCall([
      "action": "startDiscovery",
      "portType": portType
    ])
    if isOk(result) {
      emitResultIfNeeded(result, fallbackError: "Epson ePOS: falha ao iniciar discovery")
    } else {
      emitBridgeError(result, fallback: "Epson ePOS: falha ao iniciar discovery")
      emitter.emit(type: "scanStopped", message: "Epson ePOS: discovery não iniciado")
    }
  }

  func stopScan() {
    let result = bridgeCall(["action": "stopDiscovery"])
    emitResultIfNeeded(result, fallbackError: "Epson ePOS: falha ao parar discovery")
    emitter.emit(type: "scanStopped", message: "Epson ePOS: discovery parado")
  }

  func connect(deviceId: String) {
    stopScan()
    cancelAutoDisconnect()

    emitter.emit(type: "status", message: "Epson ePOS: conectando \(deviceId)...")
    let result = bridgeCall([
      "action": "connect",
      "target": deviceId,
      "printerSeries": printerSeries,
      "modelLang": modelLang,
      "connectTimeoutMs": connectTimeoutMs
    ])

    guard isOk(result) else {
      emitBridgeError(result, fallback: "Epson ePOS: falha ao conectar")
      return
    }

    connectedTarget = deviceId
    let name = devices[deviceId]?["name"] as? String ?? deviceId
    DispatchQueue.main.async { [weak self] in
      self?.emitter.emit(type: "connected", device: ["id": deviceId, "name": name])
      self?.emitter.emit(type: "ready", message: "Epson ePOS: pronto para imprimir")
    }
  }

  func disconnect() {
    cancelAutoDisconnect()
    let wasConnected = connectedTarget != nil
    let result = bridgeCall(["action": "disconnect"])
    connectedTarget = nil
    if !isOk(result) {
      emitBridgeError(result, fallback: "Epson ePOS: falha ao desconectar")
    }
    if wasConnected {
      emitter.emit(type: "disconnected", message: "Epson ePOS: desconectado")
    }
  }

  func printRaw(data: Data) {
    guard connectedTarget != nil else {
      emitter.emit(type: "error", message: "Epson ePOS: não conectado")
      return
    }
    cancelAutoDisconnect()

    emitter.emit(type: "status", message: "Epson ePOS: enviando \(data.count) bytes...")
    let result = bridgeCall([
      "action": "printRaw",
      "data": data,
      "sendTimeoutMs": sendTimeoutMs
    ])

    guard isOk(result) else {
      emitBridgeError(result, fallback: "Epson ePOS: falha ao imprimir")
      return
    }

    emitter.emit(type: "status", message: "Epson ePOS: enviado. Liberando em \(autoDisconnectMs)ms...")
    scheduleAutoDisconnect()
  }

  func snapshot() -> [[String: Any]] {
    let result = bridgeCall(["action": "snapshot"])
    if let list = result["devices"] as? [[String: Any]] {
      return list
    }
    return devices.values.sorted { left, right in
      let a = (left["name"] as? String) ?? ""
      let b = (right["name"] as? String) ?? ""
      return a.localizedCaseInsensitiveCompare(b) == .orderedAscending
    }
  }

  private let emitter = EventEmitter()
  private let bridge = EpsonEposSdkBridge()
  private var devices: [String: [String: Any]] = [:]
  private var connectedTarget: String?

  private var portType = "all"
  private var printerSeries = "tmP80ii"
  private var modelLang = "ank"
  private var connectTimeoutMs = 10000
  private var sendTimeoutMs = 10000
  private var autoDisconnectMs = 20000
  private var autoDisconnectWorkItem: DispatchWorkItem?

  private lazy var bridgeCallback: EpsonEposEventSink = { [weak self] event in
    self?.handleBridgeEvent(event)
  }

  private func bridgeCall(_ args: [String: Any]) -> [String: Any] {
    bridge.handle(args, callback: bridgeCallback)
  }

  private func handleBridgeEvent(_ event: [String: Any]) {
    if let device = event["device"] as? [String: Any],
       let id = device["id"] as? String {
      devices[id] = device
    }

    guard let type = event["type"] as? String else {
      return
    }

    let device = event["device"] as? [String: Any]
    let message = event["message"] as? String
    var extra = event
    extra.removeValue(forKey: "type")
    extra.removeValue(forKey: "device")
    extra.removeValue(forKey: "message")

    emitter.emit(type: type, message: message, device: device, extra: extra)
  }

  private func emitResultIfNeeded(_ result: [String: Any], fallbackError: String) {
    if isOk(result) {
      if let message = result["message"] as? String, !message.isEmpty {
        emitter.emit(type: "status", message: message)
      }
    } else {
      emitBridgeError(result, fallback: fallbackError)
    }
  }

  private func emitBridgeError(_ result: [String: Any], fallback: String) {
    let message = (result["message"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? fallback
    emitter.emit(type: "error", message: message)
  }

  private func isOk(_ result: [String: Any]) -> Bool {
    if let ok = result["ok"] as? Bool {
      return ok
    }
    if let ok = result["ok"] as? NSNumber {
      return ok.boolValue
    }
    return false
  }

  private func scheduleAutoDisconnect() {
    cancelAutoDisconnect()
    guard autoDisconnectMs > 0 else { return }

    let workItem = DispatchWorkItem { [weak self] in
      self?.disconnect()
    }
    autoDisconnectWorkItem = workItem
    DispatchQueue.main.asyncAfter(
        deadline: .now() + (Double(autoDisconnectMs) / 1000.0),
        execute: workItem
    )
  }

  private func cancelAutoDisconnect() {
    autoDisconnectWorkItem?.cancel()
    autoDisconnectWorkItem = nil
  }
}
