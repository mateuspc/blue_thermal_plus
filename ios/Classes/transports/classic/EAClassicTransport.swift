import Foundation
import ExternalAccessory

/// Classic transport on iOS is done via ExternalAccessory (MFi).
/// This requires:
/// - Printer paired/connected and visible in EAAccessoryManager.shared().connectedAccessories
/// - Runner Info.plist includes UISupportedExternalAccessoryProtocols
///   (e.g., com.zebra.rawport or com.honeywell.print)
final class EAClassicTransport: NSObject, PrinterTransportManager, StreamDelegate {

  // MARK: - PrinterTransportManager
  var onEvent: (([String: Any]) -> Void)? {
    didSet { emitter.sink = onEvent }
  }

  // ✅ Configurações vindas do Flutter
  // - preferredProtocol: ex "com.zebra.rawport" (nil -> auto)
  // - autoDisconnectMs: default 3000
  func applyClassicConfig(preferredProtocol: String?, autoDisconnectMs: Int?) {
    if let p = preferredProtocol {
      self.preferredProtocol = p.isEmpty ? nil : p
    }

    if let ms = autoDisconnectMs {
      self.autoDisconnectMs = max(0, ms)
    }

    emitter.emit(
        type: "status",
        message: "Classic(EA): config aplicado protocol=\(self.preferredProtocol ?? "auto") autoDisconnectMs=\(self.autoDisconnectMs)"
    )
  }

  func startScan() {
    store.clearClassic()

    emitter.emit(type: "scanStarted", message: "Classic(EA): listando acessórios conectados...")
    let accessories = EAAccessoryManager.shared().connectedAccessories

    for a in accessories {
      store.upsertClassic(a)
      emitter.emit(
          type: "deviceFound",
          device: ["id": String(a.connectionID), "name": a.name],
          extra: ["protocols": a.protocolStrings]
      )
    }

    emitter.emit(type: "scanStopped", message: "Classic(EA): lista pronta")
  }

  func stopScan() {
    // No continuous scan in EA; keep method for API symmetry
    emitter.emit(type: "scanStopped", message: "Classic(EA): stopScan (noop)")
  }

  func connect(deviceId: String) {
    cancelAutoDisconnect()

    if activeBackend == .honeywellSdk, honeywellPendingPrints > 0 {
      emitter.emit(
          type: "error",
          message: "Honeywell SDK: aguarde a impressão terminar antes de reconectar"
      )
      return
    }

    // ✅ evita trabalho/efeitos colaterais se ainda não estava conectado
    if activeBackend != .none || session != nil || outStream != nil || inStream != nil {
      disconnect()
    }

    guard let accessory = store.classicAccessory(idString: deviceId) else {
      emitter.emit(type: "error", message: "Classic(EA): acessório não encontrado: \(deviceId)")
      return
    }

    // ✅ Escolha do protocolo:
    // 1) preferredProtocol (se veio e existe no accessory)
    // 2) com.honeywell.print (se existir)
    // 3) com.zebra.rawport (se existir)
    // 4) primeiro protocol disponível
    // 5) erro se vazio
    let protocolToUse: String
    if let pref = preferredProtocol, accessory.protocolStrings.contains(pref) {
      protocolToUse = pref
    } else if accessory.protocolStrings.contains(honeywellProtocol) {
      protocolToUse = honeywellProtocol
    } else if accessory.protocolStrings.contains("com.zebra.rawport") {
      protocolToUse = "com.zebra.rawport"
    } else if let first = accessory.protocolStrings.first {
      protocolToUse = first
    } else {
      emitter.emit(type: "error", message: "Classic(EA): acessório sem protocolos (protocolStrings vazio)")
      return
    }

    if protocolToUse == honeywellProtocol, HoneywellPrinterSdkBridge.isSdkAvailable {
      connectWithHoneywellSdk(
          accessory: accessory,
          deviceId: deviceId,
          protocolString: protocolToUse
      )
      return
    }

    if protocolToUse == honeywellProtocol {
      emitter.emit(
          type: "status",
          message: "Honeywell SDK indisponível; usando ExternalAccessory como fallback"
      )
    }

    emitter.emit(type: "status", message: "Classic(EA): abrindo sessão \(accessory.name) / \(protocolToUse)")

    guard let s = EASession(accessory: accessory, forProtocol: protocolToUse) else {
      emitter.emit(
          type: "error",
          message: "Classic(EA): falha ao criar EASession. Verifique MFi e Info.plist (UISupportedExternalAccessoryProtocols)."
      )
      return
    }

    session = s
    outStream = s.outputStream
    inStream = s.inputStream
    activeBackend = .externalAccessory
    connectedDevice = ["id": deviceId, "name": accessory.name]

    didEmitReady = false

    if let o = outStream {
      o.delegate = self
      o.schedule(in: .main, forMode: .common) // ✅ melhor que .default
      o.open()
    }

    if let i = inStream {
      i.delegate = self
      i.schedule(in: .main, forMode: .common) // ✅ melhor que .default
      i.open()
    }

    emitter.emit(type: "connected", device: ["id": deviceId, "name": accessory.name])
  }

  func disconnect() {
    cancelAutoDisconnect()
    let wasConnected = (activeBackend != .none || session != nil || outStream != nil || inStream != nil)

    if activeBackend == .honeywellSdk {
      let result = honeywellBridgeCall(["action": "disconnect"])
      if !isOk(result) {
        emitBridgeError(result, fallback: "Honeywell SDK: falha ao desconectar")
        return
      }

      activeBackend = .none
      connectedDevice = nil
      honeywellReady = false
      if wasConnected {
        emitter.emit(type: "disconnected", message: "Honeywell SDK: desconectado")
      }
      return
    }

    // Para evitar duplicar READY depois
    didEmitReady = false

    // remove from runloop first
    outStream?.remove(from: .main, forMode: .common)
    inStream?.remove(from: .main, forMode: .common)

    outStream?.delegate = nil
    inStream?.delegate = nil

    outStream?.close()
    inStream?.close()

    outStream = nil
    inStream = nil
    session = nil
    activeBackend = .none
    connectedDevice = nil

    if wasConnected {
      emitter.emit(type: "disconnected", message: "Classic(EA): desconectado")
    }
  }

  func printRaw(data: Data) {
    printRaw(data: data) { _ in }
  }

  func printRaw(data: Data, completion: @escaping PrinterWriteCompletion) {
    cancelAutoDisconnect()

    if activeBackend == .honeywellSdk {
      guard honeywellReady else {
        let message = "Honeywell SDK: conexão ainda não está pronta"
        emitter.emit(type: "error", message: message)
        completion(PrinterWriteFailure(code: "not_ready", message: message))
        return
      }

      honeywellPendingPrints += 1
      let timeoutMs = honeywellDrainTimeoutMs(bytes: data.count)
      emitter.emit(
          type: "status",
          message: "Honeywell SDK: enviando \(data.count) bytes e aguardando a fila nativa..."
      )

      honeywellBridge.printRawData(
          data,
          timeoutMilliseconds: timeoutMs
      ) { [weak self] result in
        guard let self else {
          completion(
              PrinterWriteFailure(
                  code: "transport_released",
                  message: "Honeywell SDK: transporte liberado durante a impressão."
              )
          )
          return
        }

        self.honeywellPendingPrints = max(0, self.honeywellPendingPrints - 1)

        guard self.isOk(result) else {
          let failure = self.writeFailure(
              result,
              fallback: "Honeywell SDK: falha ao imprimir"
          )
          self.emitter.emit(type: "error", message: failure.message)
          completion(failure)
          return
        }

        self.emitter.emit(
            type: "status",
            message: "Honeywell SDK: fila de envio concluída (\(data.count) bytes)"
        )
        if self.honeywellPendingPrints == 0 {
          self.scheduleAutoDisconnect()
        }
        completion(nil)
      }
      return
    }

    guard let o = outStream else {
      let message = "Classic(EA): não conectado"
      emitter.emit(type: "error", message: message)
      completion(PrinterWriteFailure(code: "not_connected", message: message))
      return
    }

    guard o.hasSpaceAvailable else {
      let message = "Classic(EA): buffer cheio (sem espaço)"
      emitter.emit(type: "error", message: message)
      completion(PrinterWriteFailure(code: "buffer_full", message: message))
      return
    }

    let written = data.withUnsafeBytes { ptr -> Int in
      guard let base = ptr.bindMemory(to: UInt8.self).baseAddress else { return -1 }
      return o.write(base, maxLength: data.count)
    }

    if written <= 0 {
      let message = "Classic(EA): erro de escrita"
      emitter.emit(type: "error", message: message)
      completion(PrinterWriteFailure(code: "write_failed", message: message))
      return
    }

    if written != data.count {
      let message = "Classic(EA): escrita parcial (\(written) de \(data.count) bytes)"
      emitter.emit(type: "error", message: message)
      completion(PrinterWriteFailure(code: "partial_write", message: message))
      return
    }

    emitter.emit(type: "status", message: "📤 Classic(EA): enviado \(written) bytes (auto-disconnect \(autoDisconnectMs)ms)")

    scheduleAutoDisconnect()
    completion(nil)
  }

  // MARK: - Init/Deinit
  private let store: DeviceStore
  private let emitter = EventEmitter()
  private let honeywellBridge = HoneywellPrinterSdkBridge()

  private enum ActiveBackend {
    case none
    case externalAccessory
    case honeywellSdk
  }

  private var session: EASession?
  private var outStream: OutputStream?
  private var inStream: InputStream?

  private var didEmitReady = false
  private var activeBackend: ActiveBackend = .none
  private var connectedDevice: [String: Any]?
  private var honeywellReady = false
  private var honeywellPendingPrints = 0

  // ✅ configs
  private var preferredProtocol: String? = nil
  private var autoDisconnectMs: Int = 3000
  private let honeywellProtocol = "com.honeywell.print"
  private var autoDisconnectWorkItem: DispatchWorkItem?

  private let readBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 1024)

  init(store: DeviceStore) {
    self.store = store
    super.init()
    registerForEA()
  }

  deinit {
    autoDisconnectWorkItem?.cancel()
    readBuffer.deallocate()
    unregisterEA()
  }

  // MARK: - Honeywell PrinterSDK
  private lazy var honeywellCallback: HoneywellPrinterEventSink = { [weak self] event in
    DispatchQueue.main.async {
      self?.handleHoneywellEvent(event)
    }
  }

  private func connectWithHoneywellSdk(
      accessory: EAAccessory,
      deviceId: String,
      protocolString: String
  ) {
    activeBackend = .honeywellSdk
    connectedDevice = ["id": deviceId, "name": accessory.name]
    honeywellReady = false

    emitter.emit(
        type: "status",
        message: "Honeywell SDK: conectando \(accessory.name) / \(protocolString)..."
    )

    let result = honeywellBridgeCall([
      "action": "connect",
      "accessory": accessory,
      "deviceId": deviceId,
      "deviceName": accessory.name,
      "protocol": protocolString
    ])

    guard isOk(result) else {
      activeBackend = .none
      connectedDevice = nil
      emitBridgeError(result, fallback: "Honeywell SDK: falha ao conectar")
      return
    }

    if let message = result["message"] as? String, !message.isEmpty {
      emitter.emit(type: "status", message: message)
    }
  }

  private func handleHoneywellEvent(_ event: [String: Any]) {
    guard activeBackend == .honeywellSdk,
          let type = event["type"] as? String else {
      return
    }

    switch type {
    case "connected":
      honeywellReady = false
    case "ready":
      honeywellReady = true
    case "error", "disconnected":
      activeBackend = .none
      connectedDevice = nil
      honeywellReady = false
      cancelAutoDisconnect()
    default:
      break
    }

    let eventDevice = event["device"] as? [String: Any]
    let device = eventDevice ?? (type == "connected" ? connectedDevice : nil)
    let message = event["message"] as? String
    var extra = event
    extra.removeValue(forKey: "type")
    extra.removeValue(forKey: "device")
    extra.removeValue(forKey: "message")
    emitter.emit(type: type, message: message, device: device, extra: extra)
  }

  private func honeywellBridgeCall(_ args: [String: Any]) -> [String: Any] {
    honeywellBridge.handle(args, callback: honeywellCallback)
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

  private func emitBridgeError(_ result: [String: Any], fallback: String) {
    let message = (result["message"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? fallback
    emitter.emit(type: "error", message: message)
  }

  private func writeFailure(
      _ result: [String: Any],
      fallback: String
  ) -> PrinterWriteFailure {
    let code = (result["code"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "write_failed"
    let message = (result["message"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? fallback
    return PrinterWriteFailure(code: code, message: message)
  }

  private func honeywellDrainTimeoutMs(bytes: Int) -> Int {
    let transferEstimateMs = Int(ceil((Double(max(1, bytes)) / 2000.0) * 1000.0))
    return min(120_000, max(30_000, transferEstimateMs + 15_000))
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

  // MARK: - StreamDelegate
  func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
    switch eventCode {

    case .openCompleted:
      // openCompleted dispara para outStream e inStream -> evita duplicar READY
      if !didEmitReady, aStream == outStream {
        didEmitReady = true
        emitter.emit(type: "ready", message: "Classic(EA): output stream aberto (pronto)")
      }

    case .hasBytesAvailable:
      if aStream == inStream {
        let bytesRead = inStream?.read(readBuffer, maxLength: 1024) ?? 0
        if bytesRead > 0 {
          let data = Data(bytes: readBuffer, count: bytesRead)
          if let resp = String(data: data, encoding: .ascii) {
            let clean = resp
                .replacingOccurrences(of: "\r", with: "")
                .replacingOccurrences(of: "\n", with: "")
            emitter.emit(type: "status", message: "📥 Classic(EA): recv [\(clean)]")
          } else {
            emitter.emit(type: "status", message: "📥 Classic(EA): recv (binário)")
          }
        }
      }

    case .errorOccurred:
      emitter.emit(type: "error", message: "Classic(EA): stream error: \(aStream.streamError?.localizedDescription ?? "")")
      disconnect()

    case .endEncountered:
      disconnect()

    default:
      break
    }
  }

  // MARK: - EA notifications
  private func registerForEA() {
    NotificationCenter.default.addObserver(
        self,
        selector: #selector(accConnected),
        name: .EAAccessoryDidConnect,
        object: nil
    )
    NotificationCenter.default.addObserver(
        self,
        selector: #selector(accDisconnected),
        name: .EAAccessoryDidDisconnect,
        object: nil
    )
    EAAccessoryManager.shared().registerForLocalNotifications()
  }

  private func unregisterEA() {
    NotificationCenter.default.removeObserver(self)
  }

  @objc private func accConnected() {
    startScan()
  }

  @objc private func accDisconnected() {
    disconnect()
    startScan()
  }
}
