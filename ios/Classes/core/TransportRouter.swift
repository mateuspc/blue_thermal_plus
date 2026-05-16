import Foundation

final class TransportRouter {
  let ble: PrinterTransportManager
  let classic: PrinterTransportManager
  let epson: PrinterTransportManager

  init(ble: PrinterTransportManager, classic: PrinterTransportManager, epson: PrinterTransportManager) {
    self.ble = ble
    self.classic = classic
    self.epson = epson
  }

  func manager(for transport: TransportType) -> PrinterTransportManager {
    switch transport {
    case .ble: return ble
    case .classic: return classic
    case .epson: return epson
    }
  }
}
