import 'dart:async';
import 'dart:io'; // Import Platform
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:blue_thermal_plus/src/blue_thermal_plus.dart';
import 'package:blue_thermal_plus/api/models.dart';
import 'package:blue_thermal_plus/api/printer_config.dart';
import 'package:permission_handler/permission_handler.dart'; // Import Permission Handler

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BlueThermalPlus Example',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true),
      home: const PluginTestPage(),
    );
  }
}

class PluginTestPage extends StatefulWidget {
  const PluginTestPage({super.key});

  @override
  State<PluginTestPage> createState() => _PluginTestPageState();
}

class _PluginTestPageState extends State<PluginTestPage> {
  final bt = BlueThermalPlus();

  PrinterTransport transport = PrinterTransport.ble;

  final Map<String, PrinterDevice> devices = {};
  PrinterDevice? selected;

  bool scanning = false;
  bool connected = false;
  bool ready = false;

  String status = "Pronto";
  final List<String> logs = [];

  StreamSubscription<PrinterEvent>? sub;

  // ---------------- CONFIG STATE ----------------
  PrinterConfig config = const PrinterConfig();

  bool autoApplyOnScan = true;
  bool autoApplyOnConnect = true;

  @override
  void initState() {
    super.initState();
    sub = bt.events.listen(_handleEvent);
  }

  @override
  void dispose() {
    sub?.cancel();
    super.dispose();
  }

  // ---------------- HELPER: PERMISSIONS ----------------
  Future<bool> _checkPermissions() async {
    if (Platform.isAndroid) {
      // For Android 12+ (API 31+)
      // We need Scan and Connect. Location is technically not needed for BLE scan
      // if you don't derive physical location, but often good to check.
      if (await Permission.bluetoothScan.request().isGranted &&
          await Permission.bluetoothConnect.request().isGranted) {
        return true;
      }

      // For Android 11 or lower (API < 31)
      // Location is REQUIRED to scan for Bluetooth devices
      if (await Permission.location.request().isGranted) {
        return true;
      }

      _log("❌ Permissões negadas. Verifique as configurações.");
      return false;
    }
    // iOS usually handles permissions automatically via Info.plist usage descriptions,
    // but you can explicit check bluetooth permission if needed.
    return true;
  }

  // ---------------- LOG + EVENTS ----------------
  void _log(String msg) {
    final line = "${DateTime.now().toIso8601String().substring(11, 19)}  $msg";
    setState(() {
      logs.insert(0, line);
      if (logs.length > 200) logs.removeRange(200, logs.length);
    });
  }

  void _handleEvent(PrinterEvent e) {
    final type = e.type.toString();

    if (e.message != null && e.message!.isNotEmpty) {
      _log("[$type] ${e.message}");
      setState(() => status = e.message!);
    } else {
      _log("[$type]");
    }

    if (e.device != null) {
      final d = e.device!;
      setState(() => devices[d.id] = d);
      _log("[deviceFound] ${d.name} (${d.id})");
    }

    if (type.contains("scanStarted")) {
      setState(() => scanning = true);
    } else if (type.contains("scanStopped")) {
      setState(() => scanning = false);
    } else if (type.contains("connected")) {
      setState(() => connected = true);
    } else if (type.contains("disconnected")) {
      setState(() {
        connected = false;
        ready = false;
      });
    } else if (type.contains("ready")) {
      setState(() => ready = true);
    }
  }

  // ---------------- ACTIONS ----------------
  Future<void> _startScan() async {
    // ✅ CHECK PERMISSIONS BEFORE SCANNING
    final hasPermission = await _checkPermissions();
    if (!hasPermission) return;

    setState(() {
      devices.clear();
      selected = null;
      scanning = true;
      status = "Iniciando scan...";
    });

    _log(">>> startScan($transport)");
    await bt.startScan(transport: transport);
  }

  Future<void> _stopScan() async {
    _log(">>> stopScan($transport)");
    await bt.stopScan(transport: transport);
    setState(() => scanning = false);
  }

  Future<void> _snapshot() async {
    // Also good to check permission here for Android 11 location requirement
    final hasPermission = await _checkPermissions();
    if (!hasPermission) return;

    _log(">>> getDiscoveredDevices($transport)");
    final list = await bt.getDiscoveredDevices(transport: transport);

    setState(() {
      for (final d in list) devices[d.id] = d;
    });

    _log("Snapshot: ${list.length} devices");
  }

  Future<void> _connectSelected() async {
    final d = selected;
    if (d == null) {
      _log("⚠️ Selecione um device primeiro");
      return;
    }

    // Checking permission for Connect (Android 12)
    if (Platform.isAndroid) {
      if (!await Permission.bluetoothConnect.request().isGranted) {
        _log("❌ Permissão de conexão Bluetooth negada");
        return;
      }
    }

    // ✅ 1) Define o profile aqui (antes de conectar)
    final profile = PrinterProfiles.zebra;

    _log(">>> configure(profile=esp32)");
    await bt.configure(profile);


    _log(">>> connect(${d.id}, $transport)");
    await bt.connect(deviceId: d.id, transport: transport);
  }

  Future<void> _disconnect() async {
    _log(">>> disconnect($transport)");
    await bt.disconnect(transport: transport);
  }

  Future<void> _printTestCpcl() async {
    if (!ready) {
      _log("⚠️ Ainda não está READY (aguarde 'ready')");
      return;
    }

    final data = _cpclTestBytes();
    _log(">>> printRawBytes(${data.length} bytes, $transport)");
    await bt.printRawBytes(data, transport: transport);
  }

  Uint8List _cpclTestBytes() {
    final cpcl = <int>[];
    void add(String s) => cpcl.addAll(s.codeUnits);

    add("\r\n");
    add("! 0 200 200 500 1\r\n");
    add("PAGE-WIDTH 800\r\n");
    add("JOURNAL\r\n");
    add("T 5 0 30 30 FLUTTER TEST\r\n");
    add("T 7 0 30 80 Transport: ${transport.name}\r\n");
    add("LINE 30 160 750 160 3\r\n");
    add("BARCODE 128 1 1 50 30 200 123456789\r\n");
    add("PRINT\r\n");

    return Uint8List.fromList(cpcl);
  }

  // ---------------- UI ----------------
  @override
  Widget build(BuildContext context) {
    // ... (O restante da UI permanece idêntico) ...
    final list = devices.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    return Scaffold(
      appBar: AppBar(
        title: const Text("BlueThermalPlus - Test App"),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: Row(
                children: [
                  const Text("Transport: "),
                  const SizedBox(width: 6),
                  DropdownButton<PrinterTransport>(
                    value: transport,
                    items: const [
                      DropdownMenuItem(value: PrinterTransport.ble, child: Text("BLE")),
                      DropdownMenuItem(value: PrinterTransport.classic, child: Text("Classic")),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() {
                        transport = v;
                        devices.clear();
                        selected = null;
                        scanning = false;
                        connected = false;
                        ready = false;
                        status = "Transport alterado para ${v.name}";
                      });
                      _log("=== Transport => ${v.name} ===");
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: _StatusCard(
              status: status,
              scanning: scanning,
              connected: connected,
              ready: ready,
              transport: transport,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: scanning ? null : _startScan,
                  icon: const Icon(Icons.radar),
                  label: const Text("Start scan"),
                ),
                OutlinedButton.icon(
                  onPressed: scanning ? _stopScan : null,
                  icon: const Icon(Icons.stop),
                  label: const Text("Stop scan"),
                ),
                OutlinedButton.icon(
                  onPressed: _snapshot,
                  icon: const Icon(Icons.refresh),
                  label: const Text("Snapshot"),
                ),
                FilledButton.icon(
                  onPressed: selected == null ? null : _connectSelected,
                  icon: const Icon(Icons.link),
                  label: const Text("Connect"),
                ),
                OutlinedButton.icon(
                  onPressed: connected ? _disconnect : null,
                  icon: const Icon(Icons.link_off),
                  label: const Text("Disconnect"),
                ),
                FilledButton.icon(
                  onPressed: ready ? _printTestCpcl : null,
                  icon: const Icon(Icons.print),
                  label: const Text("Print CPCL"),
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          Expanded(
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: _DeviceList(
                    devices: list,
                    selectedId: selected?.id,
                    onSelect: (d) {
                      setState(() => selected = d);
                      _log("Selecionado: ${d.name} (${d.id})");
                    },
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: _LogPanel(logs: logs),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ... (Widgets _StatusCard, _DeviceList e _LogPanel permanecem iguais)
class _StatusCard extends StatelessWidget {
  final String status;
  final bool scanning;
  final bool connected;
  final bool ready;
  final PrinterTransport transport;

  const _StatusCard({
    required this.status,
    required this.scanning,
    required this.connected,
    required this.ready,
    required this.transport,
  });

  @override
  Widget build(BuildContext context) {
    final icon = connected ? Icons.print : Icons.bluetooth_searching;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(icon, size: 36),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Status", style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(status),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      Chip(label: Text("transport: ${transport.name}")),
                      Chip(label: Text(scanning ? "scanning" : "idle")),
                      Chip(label: Text(connected ? "connected" : "disconnected")),
                      Chip(label: Text(ready ? "ready" : "not ready")),
                    ],
                  )
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeviceList extends StatelessWidget {
  final List<PrinterDevice> devices;
  final String? selectedId;
  final void Function(PrinterDevice d) onSelect;

  const _DeviceList({
    required this.devices,
    required this.selectedId,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 0, 6, 12),
      child: Column(
        children: [
          const ListTile(
            title: Text("Dispositivos"),
            subtitle: Text("Clique para selecionar"),
            dense: true,
          ),
          const Divider(height: 1),
          Expanded(
            child: devices.isEmpty
                ? const Center(child: Text("Nenhum device ainda"))
                : ListView.builder(
              itemCount: devices.length,
              itemBuilder: (context, i) {
                final d = devices[i];
                final selected = d.id == selectedId;

                return ListTile(
                  selected: selected,
                  leading: const Icon(Icons.bluetooth),
                  title: Text(d.name),
                  subtitle: Text(d.id),
                  trailing: selected ? const Icon(Icons.check_circle) : null,
                  onTap: () => onSelect(d),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _LogPanel extends StatelessWidget {
  final List<String> logs;

  const _LogPanel({required this.logs});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.fromLTRB(6, 0, 12, 12),
      child: Column(
        children: [
          const ListTile(
            title: Text("Logs / Events"),
            subtitle: Text("Realtime do plugin"),
            dense: true,
          ),
          const Divider(height: 1),
          Expanded(
            child: logs.isEmpty
                ? const Center(child: Text("Sem logs ainda"))
                : ListView.builder(
              itemCount: logs.length,
              itemBuilder: (context, i) {
                final l = logs[i];
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Text(
                    l,
                    style: const TextStyle(fontFamily: "monospace", fontSize: 12),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}