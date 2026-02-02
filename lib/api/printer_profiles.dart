import 'printer_config.dart';

class PrinterProfiles {
  const PrinterProfiles._();

  static const zebra = PrinterConfig(
    ble: BleConfig(
      serviceUuid: "38EB4A80-C570-11E3-9507-0002A5D5C51B",
      writeCharacteristicUuid: "38EB4A82-C570-11E3-9507-0002A5D5C51B",
      chunkSize: 20,
      chunkDelayMs: 10,
      autoDisconnectMs: 3000,
    ),
    classic: ClassicConfig(
      preferredProtocol: "com.zebra.rawport",
      autoDisconnectMs: 3000,
    ),
  );

  /// ✅ ESP32 Virtual Printer (seu firmware)
  static const esp32VirtualPrinter = PrinterConfig(
    ble: BleConfig(
      serviceUuid: "12345678-1234-1234-1234-1234567890AB",
      writeCharacteristicUuid: "87654321-4321-4321-4321-BA0987654321",

      // Recomendo começar assim para ficar estável:
      // - 20 é o "seguro" (MTU padrão). Se estiver ok, sobe pra 60/100.
      chunkSize: 20,

      // Como é writeWithoutResponse, geralmente 0–5ms funciona.
      // Se perder chunk, sobe pra 10ms.
      chunkDelayMs: 2,

      // Só pra “limpar” a conexão depois do teste
      autoDisconnectMs: 1500,
    ),

    // Classic não aplica no ESP32 (MFi)
    classic: ClassicConfig(preferredProtocol: null, autoDisconnectMs: 3000),
  );
}
