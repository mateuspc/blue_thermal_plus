import 'dart:typed_data';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import '../api/models.dart';
import '../api/printer_config.dart';
import 'blue_thermal_plus_method_channel.dart';

abstract class BlueThermalPlusPlatform extends PlatformInterface {
  BlueThermalPlusPlatform() : super(token: _token);
  static final Object _token = Object();

  static BlueThermalPlusPlatform _instance = MethodChannelBlueThermalPlus();
  static BlueThermalPlusPlatform get instance => _instance;

  static set instance(BlueThermalPlusPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  /// Stream único de eventos (status, deviceFound, connected, etc.)
  Stream<PrinterEvent> get events =>
      throw UnimplementedError('events not implemented');

  Future<void> configure(PrinterConfig config) {
    throw UnimplementedError('configure() has not been implemented.');
  }

  Future<void> startScan({PrinterTransport transport = PrinterTransport.ble}) {
    throw UnimplementedError('startScan not implemented');
  }

  Future<void> stopScan({PrinterTransport transport = PrinterTransport.ble}) {
    throw UnimplementedError('stopScan not implemented');
  }

  Future<void> connect({
    required String deviceId,
    PrinterTransport transport = PrinterTransport.ble,
  }) {
    throw UnimplementedError('connect not implemented');
  }

  Future<void> disconnect({PrinterTransport transport = PrinterTransport.ble}) {
    throw UnimplementedError('disconnect not implemented');
  }

  Future<void> printRawBytes(
    Uint8List data, {
    PrinterTransport transport = PrinterTransport.ble,
  }) {
    throw UnimplementedError('printRawBytes not implemented');
  }

  Future<List<PrinterDevice>> getDiscoveredDevices({
    PrinterTransport transport = PrinterTransport.ble,
  });
}
