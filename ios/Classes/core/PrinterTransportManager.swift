import Foundation

struct PrinterWriteFailure: Error {
  let code: String
  let message: String
}

typealias PrinterWriteCompletion = (PrinterWriteFailure?) -> Void

protocol PrinterTransportManager: AnyObject {
  /// Emits events to Flutter as a Dictionary payload.
  /// Example:
  /// { "type": "deviceFound", "device": { "id": "...", "name": "..." }, "message": "..." }
  var onEvent: (([String: Any]) -> Void)? { get set }

  func startScan()
  func stopScan()

  func connect(deviceId: String)
  func disconnect()

  func printRaw(data: Data)
}
