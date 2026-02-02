import Foundation
import CoreBluetooth

/// BLE transport genérico (baseado no seu ZebraBLETransport que já funciona).
/// - Scans for peripherals (withServices: nil) and emite deviceFound.
/// - Connect usando CBPeripheral guardado (deviceId = peripheral.identifier.uuidString).
/// - Descobre service/characteristic alvo e imprime com chunking.
/// - ✅ Genérico via applyBleConfig(serviceUuid, writeCharUuid, chunkSize, chunkDelayUs, autoDisconnectMs)
/// - ✅ Defaults Zebra para não quebrar nada.
final class ZebraBLETransport: NSObject,
                               PrinterTransportManager,
                               CBCentralManagerDelegate,
                               CBPeripheralDelegate {

  // MARK: - PrinterTransportManager
  var onEvent: (([String: Any]) -> Void)? {
    didSet { emitter.sink = onEvent }
  }

  /// ✅ Configuração dinâmica via Flutter
  /// - Chame antes de connect() (recomendado).
  /// - Se algum valor vier null/vazio, cai para defaults Zebra.
  func applyBleConfig(
      serviceUuid: String?,
      writeCharUuid: String?,
      chunkSize: Int? = nil,
      chunkDelayUs: Int? = nil,
      autoDisconnectMs: Int? = nil
  ) {
    let s = (serviceUuid?.isEmpty == false) ? serviceUuid! : zebraDefaultServiceUuid
    let w = (writeCharUuid?.isEmpty == false) ? writeCharUuid! : zebraDefaultWriteCharUuid

    self.serviceUUID = CBUUID(string: s)
    self.writeCharUUID = CBUUID(string: w)

    if let chunkSize {
      self.chunkSize = max(20, chunkSize) // mínimo seguro
    }
    if let chunkDelayUs {
      self.chunkDelayUs = useconds_t(max(0, chunkDelayUs))
    }
    if let autoDisconnectMs {
      self.autoDisconnectMs = max(0, autoDisconnectMs)
    }

    emitter.emit(
        type: "status",
        message: "BLE: config aplicado service=\(s) write=\(w) chunk=\(self.chunkSize) delayUs=\(self.chunkDelayUs) autoDiscMs=\(self.autoDisconnectMs)"
    )
  }

  func startScan() {
    // Arma o scan e inicia assim que central ficar poweredOn.
    pendingScan = true
    store.clearBle()
    emitter.emit(type: "scanStarted", message: "BLE: preparando scan... (state=\(central.state.rawValue))")

    if central.state == .poweredOn {
      startScanInternal()
    } else {
      emitter.emit(type: "status", message: "BLE: aguardando central ficar poweredOn...")
    }
  }

  func stopScan() {
    pendingScan = false
    central.stopScan()
    emitter.emit(type: "scanStopped", message: "BLE: scan parado")
  }

  func connect(deviceId: String) {
    guard let peripheral = store.blePeripheral(idString: deviceId) else {
      emitter.emit(type: "error", message: "BLE: deviceId não encontrado no scan: \(deviceId)")
      return
    }

    stopScan()

    connectedPeripheral = peripheral
    connectedPeripheral?.delegate = self
    writeCharacteristic = nil

    emitter.emit(type: "status", message: "BLE: conectando a \(peripheral.name ?? "Dispositivo")...")
    central.connect(peripheral, options: nil)
  }

  func disconnect() {
    pendingScan = false
    if let p = connectedPeripheral {
      central.cancelPeripheralConnection(p)
    }
  }

  func printRaw(data: Data) {
    guard let peripheral = connectedPeripheral, let char = writeCharacteristic else {
      emitter.emit(type: "error", message: "BLE: não pronto (sem peripheral/characteristic)")
      return
    }

    emitter.emit(type: "status", message: "BLE: enviando dados...")

    let chunkSizeLocal = chunkSize
    let delayUsLocal = chunkDelayUs
    let autoDiscMsLocal = autoDisconnectMs

    DispatchQueue.global(qos: .userInitiated).async {
      var offset = 0

      while offset < data.count {
        let amount = min(data.count - offset, chunkSizeLocal)
        let chunk = data.subdata(in: offset..<(offset + amount))

        let writeType: CBCharacteristicWriteType =
            char.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse

        peripheral.writeValue(chunk, for: char, type: writeType)

        offset += amount
        if delayUsLocal > 0 { usleep(delayUsLocal) }
      }

      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        self.emitter.emit(type: "status", message: "✅ BLE enviado! Liberando em \(autoDiscMsLocal)ms...")
        let delay = Double(autoDiscMsLocal) / 1000.0
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
          self?.disconnect()
        }
      }
    }
  }

  // MARK: - Private
  private let store: DeviceStore
  private let emitter = EventEmitter()

  private var central: CBCentralManager!
  private var connectedPeripheral: CBPeripheral?
  private var writeCharacteristic: CBCharacteristic?

  private var pendingScan: Bool = false

  // ✅ Defaults Zebra (mantém comportamento original)
  private let zebraDefaultServiceUuid = "38EB4A80-C570-11E3-9507-0002A5D5C51B"
  private let zebraDefaultWriteCharUuid = "38EB4A82-C570-11E3-9507-0002A5D5C51B"

  // ✅ UUIDs em uso (customizáveis)
  private var serviceUUID: CBUUID
  private var writeCharUUID: CBUUID

  // ✅ Chunking configurável (defaults iguais ao seu)
  private var chunkSize: Int = 100
  private var chunkDelayUs: useconds_t = 10_000

  // ✅ Auto-disconnect configurável (default igual ao seu)
  private var autoDisconnectMs: Int = 3000

  init(store: DeviceStore) {
    self.store = store

    // inicia com defaults Zebra
    self.serviceUUID = CBUUID(string: zebraDefaultServiceUuid)
    self.writeCharUUID = CBUUID(string: zebraDefaultWriteCharUuid)

    super.init()

    self.central = CBCentralManager(
        delegate: self,
        queue: nil,
        options: [CBCentralManagerOptionShowPowerAlertKey: true]
    )
  }

  private func startScanInternal() {
    emitter.emit(type: "status", message: "BLE: iniciando scan (poweredOn)")
    central.scanForPeripherals(
        withServices: nil,
        options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
    )
  }

  // MARK: - CBCentralManagerDelegate
  func centralManagerDidUpdateState(_ central: CBCentralManager) {
    switch central.state {
    case .poweredOn:
      emitter.emit(type: "status", message: "BLE: Bluetooth ligado ✅")
      if pendingScan { startScanInternal() }

    case .poweredOff:
      emitter.emit(type: "error", message: "BLE: Bluetooth desligado")

    case .unauthorized:
      emitter.emit(type: "error", message: "BLE: sem permissão. Verifique Info.plist (NSBluetoothAlwaysUsageDescription).")

    case .unsupported:
      emitter.emit(type: "error", message: "BLE: não suportado neste device")

    case .resetting, .unknown:
      emitter.emit(type: "status", message: "BLE: inicializando (state=\(central.state.rawValue))...")

    @unknown default:
      emitter.emit(type: "status", message: "BLE: state desconhecido")
    }
  }

  func centralManager(_ central: CBCentralManager,
                      didDiscover peripheral: CBPeripheral,
                      advertisementData: [String : Any],
                      rssi RSSI: NSNumber) {

    // Não bloqueia sem name (muitos vêm sem nome)
    if store.ble[peripheral.identifier] == nil {
      store.upsertBle(peripheral)

      let name = peripheral.name
          ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
          ?? "Sem Nome"

      emitter.emit(type: "deviceFound", device: [
        "id": peripheral.identifier.uuidString,
        "name": name
      ])
    }
  }

  func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
    emitter.emit(type: "connected", device: [
      "id": peripheral.identifier.uuidString,
      "name": peripheral.name ?? ""
    ])

    // ✅ mais eficiente: descobre só o service alvo
    peripheral.discoverServices([serviceUUID])
  }

  func centralManager(_ central: CBCentralManager,
                      didDisconnectPeripheral peripheral: CBPeripheral,
                      error: Error?) {
    connectedPeripheral = nil
    writeCharacteristic = nil
    emitter.emit(type: "disconnected", message: "BLE: desconectado")
  }

  func centralManager(_ central: CBCentralManager,
                      didFailToConnect peripheral: CBPeripheral,
                      error: Error?) {
    emitter.emit(type: "error", message: "BLE: falha ao conectar: \(error?.localizedDescription ?? "erro")")
  }

  // MARK: - CBPeripheralDelegate
  func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
    guard error == nil else {
      emitter.emit(type: "error", message: "BLE: erro ao descobrir serviços: \(error!.localizedDescription)")
      return
    }
    guard let services = peripheral.services else {
      emitter.emit(type: "error", message: "BLE: services nil")
      return
    }

    guard let targetService = services.first(where: { $0.uuid == serviceUUID }) else {
      let found = services.map { $0.uuid.uuidString }.joined(separator: ", ")
      emitter.emit(type: "status", message: "BLE: serviço alvo NÃO encontrado (target=\(serviceUUID.uuidString)). Encontrados: [\(found)]")
      return
    }

    emitter.emit(type: "status", message: "BLE: serviço encontrado (\(serviceUUID.uuidString)), buscando characteristic...")
    peripheral.discoverCharacteristics([writeCharUUID], for: targetService)
  }

  func peripheral(_ peripheral: CBPeripheral,
                  didDiscoverCharacteristicsFor service: CBService,
                  error: Error?) {
    guard error == nil else {
      emitter.emit(type: "error", message: "BLE: erro ao descobrir characteristics: \(error!.localizedDescription)")
      return
    }
    guard let chars = service.characteristics else {
      emitter.emit(type: "error", message: "BLE: characteristics nil")
      return
    }

    guard let targetChar = chars.first(where: { $0.uuid == writeCharUUID }) else {
      let found = chars.map { $0.uuid.uuidString }.joined(separator: ", ")
      emitter.emit(type: "status", message: "BLE: write char NÃO encontrada (target=\(writeCharUUID.uuidString)). Encontradas: [\(found)]")
      return
    }

    writeCharacteristic = targetChar
    emitter.emit(type: "ready", message: "BLE: pronto para imprimir (write=\(writeCharUUID.uuidString))")
  }
}
