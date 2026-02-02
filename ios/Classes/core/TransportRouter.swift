import Foundation

final class TransportRouter {
  let ble: PrinterTransportManager
  let classic: PrinterTransportManager

  init(ble: PrinterTransportManager, classic: PrinterTransportManager) {
    self.ble = ble
    self.classic = classic
  }

  func manager(for transport: TransportType) -> PrinterTransportManager {
    switch transport {
    case .ble: return ble
    case .classic: return classic
    }
  }
}
