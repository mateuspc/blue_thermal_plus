enum PrinterTransport { ble, classic }

class PrinterDevice {
  final String id;
  final String name;

  PrinterDevice({required this.id, required this.name});

  factory PrinterDevice.fromMap(Map<dynamic, dynamic> map) => PrinterDevice(
    id: map['id'] as String,
    name: (map['name'] as String?) ?? 'Unknown',
  );
}

enum PrinterEventType {
  status,
  scanStarted,
  scanStopped,
  deviceFound,
  connected,
  disconnected,
  ready,
  error,
}

class PrinterEvent {
  final PrinterEventType type;
  final String? message;
  final PrinterDevice? device;
  final List<String>? protocols; // opcional (EA classic)

  PrinterEvent({
    required this.type,
    this.message,
    this.device,
    this.protocols,
  });

  factory PrinterEvent.fromMap(Map<dynamic, dynamic> map) {
    final typeStr = (map['type'] as String?) ?? 'status';
    final type = PrinterEventType.values.firstWhere(
          (e) => e.name == typeStr,
      orElse: () => PrinterEventType.status,
    );

    final deviceVal = map['device'];
    final device = deviceVal is Map ? PrinterDevice.fromMap(deviceVal) : null;

    final protVal = map['protocols'];
    final protocols = protVal is List ? protVal.map((e) => e.toString()).toList() : null;

    return PrinterEvent(
      type: type,
      message: map['message'] as String?,
      device: device,
      protocols: protocols,
    );
  }
}
