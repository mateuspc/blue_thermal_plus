import Foundation

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
