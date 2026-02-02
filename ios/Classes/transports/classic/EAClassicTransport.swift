import Foundation
import ExternalAccessory

/// Classic transport on iOS is done via ExternalAccessory (MFi).
/// This requires:
/// - Printer paired/connected and visible in EAAccessoryManager.shared().connectedAccessories
/// - Runner Info.plist includes UISupportedExternalAccessoryProtocols (e.g., com.zebra.rawport)
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
    // ✅ evita trabalho/efeitos colaterais se ainda não estava conectado
    if session != nil || outStream != nil || inStream != nil {
      disconnect()
    }

    guard let accessory = store.classicAccessory(idString: deviceId) else {
      emitter.emit(type: "error", message: "Classic(EA): acessório não encontrado: \(deviceId)")
      return
    }

    // ✅ Escolha do protocolo:
    // 1) preferredProtocol (se veio e existe no accessory)
    // 2) com.zebra.rawport (se existir)
    // 3) primeiro protocol disponível
    // 4) erro se vazio
    let protocolToUse: String
    if let pref = preferredProtocol, accessory.protocolStrings.contains(pref) {
      protocolToUse = pref
    } else if accessory.protocolStrings.contains("com.zebra.rawport") {
      protocolToUse = "com.zebra.rawport"
    } else if let first = accessory.protocolStrings.first {
      protocolToUse = first
    } else {
      emitter.emit(type: "error", message: "Classic(EA): acessório sem protocolos (protocolStrings vazio)")
      return
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
    let wasConnected = (session != nil || outStream != nil || inStream != nil)

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

    if wasConnected {
      emitter.emit(type: "disconnected", message: "Classic(EA): desconectado")
    }
  }

  func printRaw(data: Data) {
    guard let o = outStream else {
      emitter.emit(type: "error", message: "Classic(EA): não conectado")
      return
    }

    guard o.hasSpaceAvailable else {
      emitter.emit(type: "error", message: "Classic(EA): buffer cheio (sem espaço)")
      return
    }

    let written = data.withUnsafeBytes { ptr -> Int in
      guard let base = ptr.bindMemory(to: UInt8.self).baseAddress else { return -1 }
      return o.write(base, maxLength: data.count)
    }

    if written <= 0 {
      emitter.emit(type: "error", message: "Classic(EA): erro de escrita")
      return
    }

    emitter.emit(type: "status", message: "📤 Classic(EA): enviado \(written) bytes (auto-disconnect \(autoDisconnectMs)ms)")

    let delaySec = Double(autoDisconnectMs) / 1000.0
    DispatchQueue.main.asyncAfter(deadline: .now() + delaySec) { [weak self] in
      self?.disconnect()
    }
  }

  // MARK: - Init/Deinit
  private let store: DeviceStore
  private let emitter = EventEmitter()

  private var session: EASession?
  private var outStream: OutputStream?
  private var inStream: InputStream?

  private var didEmitReady = false

  // ✅ configs
  private var preferredProtocol: String? = nil
  private var autoDisconnectMs: Int = 3000

  private let readBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 1024)

  init(store: DeviceStore) {
    self.store = store
    super.init()
    registerForEA()
  }

  deinit {
    readBuffer.deallocate()
    unregisterEA()
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
