import 'dart:async';
import 'package:flutter/services.dart';

import '../api/models.dart';
import '../api/printer_config.dart';
import 'blue_thermal_plus_platform_interface.dart';

class MethodChannelBlueThermalPlus extends BlueThermalPlusPlatform {
  static const MethodChannel _method = MethodChannel(
    'blue_thermal_plus/methods',
  );
  static const EventChannel _events = EventChannel('blue_thermal_plus/events');

  Stream<PrinterEvent>? _cached;

  @override
  Stream<PrinterEvent> get events {
    _cached ??= _events.receiveBroadcastStream().map((dynamic e) {
      return PrinterEvent.fromMap(e as Map<dynamic, dynamic>);
    });
    return _cached!;
  }

  /// ✅ Envia configurações para o lado nativo (iOS/Android).
  /// Use antes de connect/print quando precisar trocar UUID, chunk, protocolo etc.
  @override
  Future<void> configure(PrinterConfig config) {
    return _method.invokeMethod('configure', config.toMap());
  }

  @override
  Future<void> startScan({PrinterTransport transport = PrinterTransport.ble}) {
    return _method.invokeMethod('startScan', {'transport': transport.name});
  }

  @override
  Future<void> stopScan({PrinterTransport transport = PrinterTransport.ble}) {
    return _method.invokeMethod('stopScan', {'transport': transport.name});
  }

  @override
  Future<List<PrinterDevice>> getDiscoveredDevices({
    PrinterTransport transport = PrinterTransport.ble,
  }) async {
    final list = await _method.invokeMethod<List<dynamic>>(
      'getDiscoveredDevices',
      {'transport': transport.name},
    );

    final safe = list ?? const [];
    return safe.whereType<Map>().map((m) {
      final mm = Map<String, dynamic>.from(m);
      return PrinterDevice.fromMap(mm);
    }).toList();
  }

  @override
  Future<void> connect({
    required String deviceId,
    PrinterTransport transport = PrinterTransport.ble,
  }) {
    return _method.invokeMethod('connect', {
      'deviceId': deviceId,
      'transport': transport.name,
    });
  }

  @override
  Future<void> disconnect({PrinterTransport transport = PrinterTransport.ble}) {
    return _method.invokeMethod('disconnect', {'transport': transport.name});
  }

  @override
  Future<void> printRawBytes(
    Uint8List data, {
    PrinterTransport transport = PrinterTransport.ble,
  }) {
    return _method.invokeMethod('printRawBytes', {
      'data': data,
      'transport': transport.name,
    });
  }
}
