// lib/api/printer_config.dart

class BleConfig {
  /// Se null -> usa o default do iOS/Android (ex: Zebra UUIDs) ou tenta descobrir.
  final String? serviceUuid;

  /// Se null -> usa o default do iOS/Android (ex: Zebra write char) ou tenta descobrir.
  final String? writeCharacteristicUuid;

  /// Chunking
  final int chunkSize; // default: 100
  final int chunkDelayMs; // default: 10

  /// auto-disconnect após print
  final int autoDisconnectMs; // default: 3000

  const BleConfig({
    this.serviceUuid,
    this.writeCharacteristicUuid,
    this.chunkSize = 100,
    this.chunkDelayMs = 10,
    this.autoDisconnectMs = 3000,
  });

  Map<String, dynamic> toMap() => {
    "serviceUuid": serviceUuid,
    "writeCharacteristicUuid": writeCharacteristicUuid,
    "chunkSize": chunkSize,
    "chunkDelayMs": chunkDelayMs,
    "autoDisconnectMs": autoDisconnectMs,
  };
}

class ClassicConfig {
  /// Ex: "com.zebra.rawport"
  /// Se null -> usa o primeiro protocolo disponível do accessory.
  final String? preferredProtocol;

  final int autoDisconnectMs; // default: 3000

  const ClassicConfig({this.preferredProtocol, this.autoDisconnectMs = 3000});

  Map<String, dynamic> toMap() => {
    "preferredProtocol": preferredProtocol,
    "autoDisconnectMs": autoDisconnectMs,
  };
}

class PrinterConfig {
  final BleConfig ble;
  final ClassicConfig classic;

  const PrinterConfig({
    this.ble = const BleConfig(),
    this.classic = const ClassicConfig(),
  });

  Map<String, dynamic> toMap() => {
    "ble": ble.toMap(),
    "classic": classic.toMap(),
  };
}
