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
    this.autoDisconnectMs = 20000,
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

  final int autoDisconnectMs; // default: 20000

  const ClassicConfig({this.preferredProtocol, this.autoDisconnectMs = 20000});

  Map<String, dynamic> toMap() => {
    "preferredProtocol": preferredProtocol,
    "autoDisconnectMs": autoDisconnectMs,
  };
}

enum EpsonPortType {
  all,
  tcp,
  bluetooth,
  usb,
  bluetoothLe;

  String get nativeValue {
    switch (this) {
      case EpsonPortType.all:
        return 'all';
      case EpsonPortType.tcp:
        return 'tcp';
      case EpsonPortType.bluetooth:
        return 'bluetooth';
      case EpsonPortType.usb:
        return 'usb';
      case EpsonPortType.bluetoothLe:
        return 'ble';
    }
  }
}

enum EpsonPrinterSeries {
  tmP80ii;

  String get nativeValue {
    switch (this) {
      case EpsonPrinterSeries.tmP80ii:
        return 'tmP80ii';
    }
  }
}

class EpsonConfig {
  /// ePOS discovery port type.
  /// Use [EpsonPortType.bluetoothLe] for BLE-only discovery, or
  /// [EpsonPortType.bluetooth] for MFi Bluetooth Classic.
  final EpsonPortType portType;

  /// Printer model used to create the ePOS printer instance.
  final EpsonPrinterSeries printerSeries;

  /// ePOS language model. "ank" is the default Epson sample value.
  final String modelLang;

  final int connectTimeoutMs;
  final int sendTimeoutMs;
  final int autoDisconnectMs;

  const EpsonConfig({
    this.portType = EpsonPortType.all,
    this.printerSeries = EpsonPrinterSeries.tmP80ii,
    this.modelLang = 'ank',
    this.connectTimeoutMs = 10000,
    this.sendTimeoutMs = 10000,
    this.autoDisconnectMs = 20000,
  });

  Map<String, dynamic> toMap() => {
    "portType": portType.nativeValue,
    "printerSeries": printerSeries.nativeValue,
    "modelLang": modelLang,
    "connectTimeoutMs": connectTimeoutMs,
    "sendTimeoutMs": sendTimeoutMs,
    "autoDisconnectMs": autoDisconnectMs,
  };
}

class PrinterConfig {
  final BleConfig ble;
  final ClassicConfig classic;
  final EpsonConfig epson;

  const PrinterConfig({
    this.ble = const BleConfig(),
    this.classic = const ClassicConfig(),
    this.epson = const EpsonConfig(),
  });

  Map<String, dynamic> toMap() => {
    "ble": ble.toMap(),
    "classic": classic.toMap(),
    "epson": epson.toMap(),
  };
}
