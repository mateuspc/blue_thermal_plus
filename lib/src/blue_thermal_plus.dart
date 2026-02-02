import 'dart:typed_data';
import '../api/models.dart';
import '../api/printer_config.dart';
import 'blue_thermal_plus_platform_interface.dart';
export '../api/printer_profiles.dart';
export '../api/printer_config.dart';

class BlueThermalPlus {
  Stream<PrinterEvent> get events => BlueThermalPlusPlatform.instance.events;

  /// ✅ Configura o plugin (BLE/Classic) antes de conectar/printar.
  /// Pode chamar 1x no início do app, ou sempre que trocar de impressora/perfil.
  Future<void> configure(PrinterConfig config) {
    return BlueThermalPlusPlatform.instance.configure(config);
  }

  Future<void> startScan({PrinterTransport transport = PrinterTransport.ble}) {
    return BlueThermalPlusPlatform.instance.startScan(transport: transport);
  }

  Future<void> stopScan({PrinterTransport transport = PrinterTransport.ble}) {
    return BlueThermalPlusPlatform.instance.stopScan(transport: transport);
  }

  Future<void> connect({
    required String deviceId,
    PrinterTransport transport = PrinterTransport.ble,
  }) {
    return BlueThermalPlusPlatform.instance.connect(
      deviceId: deviceId,
      transport: transport,
    );
  }

  Future<void> disconnect({PrinterTransport transport = PrinterTransport.ble}) {
    return BlueThermalPlusPlatform.instance.disconnect(transport: transport);
  }

  Future<void> printRawBytes(
    Uint8List data, {
    PrinterTransport transport = PrinterTransport.ble,
  }) {
    return BlueThermalPlusPlatform.instance.printRawBytes(
      data,
      transport: transport,
    );
  }

  Future<List<PrinterDevice>> getDiscoveredDevices({
    PrinterTransport transport = PrinterTransport.ble,
  }) {
    return BlueThermalPlusPlatform.instance.getDiscoveredDevices(
      transport: transport,
    );
  }
}
