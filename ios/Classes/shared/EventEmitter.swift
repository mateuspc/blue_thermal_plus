import Foundation

final class EventEmitter {
  var sink: (([String: Any]) -> Void)?

  func emit(type: String, message: String? = nil, device: [String: Any]? = nil, extra: [String: Any]? = nil) {
    var payload: [String: Any] = ["type": type]
    if let message { payload["message"] = message }
    if let device { payload["device"] = device }
    if let extra {
      for (k, v) in extra { payload[k] = v }
    }
    sink?(payload)
  }
}
