import Foundation
import CoreBluetooth
import ExternalAccessory

final class DeviceStore {

  // MARK: - BLE
  private(set) var ble: [UUID: CBPeripheral] = [:]

  func upsertBle(_ p: CBPeripheral) { ble[p.identifier] = p }

  func blePeripheral(idString: String) -> CBPeripheral? {
    guard let uuid = UUID(uuidString: idString) else { return nil }
    return ble[uuid]
  }

  func clearBle() { ble.removeAll() }

  /// Snapshot serializável para o Flutter (List<Map>)
  func snapshotBle() -> [[String: Any]] {
    let peripherals = ble.values.sorted { (a, b) in
      (a.name ?? "").localizedCaseInsensitiveCompare(b.name ?? "") == .orderedAscending
    }

    return peripherals.map { p in
      [
        "id": p.identifier.uuidString,
        "name": p.name ?? "Dispositivo Sem Nome"
      ]
    }
  }

  // MARK: - Classic (ExternalAccessory)
  private(set) var classic: [Int: EAAccessory] = [:]

  func upsertClassic(_ a: EAAccessory) { classic[a.connectionID] = a }

  func classicAccessory(idString: String) -> EAAccessory? {
    guard let id = Int(idString) else { return nil }
    return classic[id]
  }

  func clearClassic() { classic.removeAll() }

  /// Snapshot serializável para o Flutter (List<Map>)
  func snapshotClassic() -> [[String: Any]] {
    let accessories = classic.values.sorted { (a, b) in
      a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
    }

    return accessories.map { a in
      [
        "id": "\(a.connectionID)",
        "name": a.name,
        "protocols": a.protocolStrings
      ]
    }
  }

  func snapshot(for transport: TransportType) -> [[String: Any]] {
    switch transport {
    case .ble:
      return snapshotBle()
    case .classic:
      return snapshotClassic()
    }
  }
}
