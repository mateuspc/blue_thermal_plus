import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:blue_thermal_plus/src/blue_thermal_plus.dart';
import 'package:blue_thermal_plus/api/models.dart';
import 'package:blue_thermal_plus/api/printer_config.dart';
import 'package:permission_handler/permission_handler.dart';

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

  // ---------------- STRATEGY ----------------
  final IPrinterStrategy bigStrategy = AutoCtbTestPrinterStrategy();

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
      if (await Permission.bluetoothScan.request().isGranted &&
          await Permission.bluetoothConnect.request().isGranted) {
        return true;
      }

      if (await Permission.location.request().isGranted) {
        return true;
      }

      _log("❌ Permissões negadas. Verifique as configurações.");
      return false;
    }
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

    if (Platform.isAndroid) {
      if (!await Permission.bluetoothConnect.request().isGranted) {
        _log("❌ Permissão de conexão Bluetooth negada");
        return;
      }
    }

    final profile = PrinterProfiles.zebra;

    _log(">>> configure(profile=zebra)");
    await bt.configure(profile);

    _log(">>> connect(${d.id}, $transport)");
    await bt.connect(deviceId: d.id, transport: transport);
  }

  Future<void> _disconnect() async {
    _log(">>> disconnect($transport)");
    await bt.disconnect(transport: transport);
  }

  Future<void> _printBigAutoCtb() async {
    if (!ready) {
      _log("⚠️ Ainda não está READY (aguarde 'ready')");
      return;
    }

    // Aqui você pode passar um Map fake, se quiser parametrizar no futuro:
    final fakeData = {
      "ait": "CTB-2026-000123",
      "placa": "ABC1D23",
      "dataHora": "05/02/2026 10:32",
    };

    final bytesList = await bigStrategy.generateBytes(fakeData);
    final data = Uint8List.fromList(bytesList);

    _log(">>> printRawBytes(BIG ${data.length} bytes, $transport)");
    await bt.printRawBytes(data, transport: transport);
  }

  // ---------------- UI ----------------
  @override
  Widget build(BuildContext context) {
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
                      DropdownMenuItem(
                        value: PrinterTransport.ble,
                        child: Text("BLE"),
                      ),
                      DropdownMenuItem(
                        value: PrinterTransport.classic,
                        child: Text("Classic"),
                      ),
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

                // ✅ NOVO BOTÃO: impressão grande
                FilledButton.icon(
                  onPressed: ready ? _printBigAutoCtb : null,
                  icon: const Icon(Icons.receipt_long),
                  label: const Text("Print BIG (Auto CTB)"),
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
                Expanded(flex: 2, child: _LogPanel(logs: logs)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ==================== STRATEGY (SEU CÓDIGO) ====================

abstract class IPrinterStrategy {
  Future<List<int>> generateBytes(dynamic data);
}

class AutoCtbTestPrinterStrategy implements IPrinterStrategy {
  @override
  Future<List<int>> generateBytes(dynamic data) async {
    final cpcl = <int>[];
    void add(String s) => cpcl.addAll(s.codeUnits);

    // Começo "limpo"
    add("\r\n");

    add("\r\n");
    add("! 0 200 200 4000 1\r\n");
    add("PAGE-WIDTH 800\r\n");
    add("JOURNAL\r\n");
    add("T 5 0 30 30 TESTE DE IMPRESSAO 2\r\n");
    // add("T 7 0 30 80 Modulo Clean Arch\r\n");
    // add("T 7 0 30 120 Modulo Clean Arch\r\n");
    int y = 80;

    void row(String produto, String valor) {
      add("T 7 0 30 $y $produto: $valor\r\n");
      y += 30;
    }

    row("Arroz 5kg", "R\$ 28,90");
    row("Feijão carioca 1kg", "R\$ 8,50");
    row("Macarrão espaguete", "R\$ 4,20");
    row("Óleo de soja 900ml", "R\$ 7,80");
    row("Açúcar refinado 1kg", "R\$ 5,10");
    row("Café torrado 500g", "R\$ 14,90");
    row("Leite integral 1L", "R\$ 4,80");
    row("Margarina 500g", "R\$ 6,40");
    row("Farinha de trigo 1kg", "R\$ 4,60");
    row("Biscoito recheado", "R\$ 3,90");
    row("Molho de tomate", "R\$ 2,70");
    row("Refrigerante 2L", "R\$ 8,99");
    row("Suco de laranja 1L", "R\$ 6,50");
    row("Queijo muçarela 300g", "R\$ 12,80");
    row("Presunto fatiado", "R\$ 9,40");
    row("Frango congelado kg", "R\$ 11,90");
    row("Carne moída kg", "R\$ 24,90");
    row("Ovos dúzia", "R\$ 9,20");
    row("Pão de forma", "R\$ 7,30");
    row("Manteiga 200g", "R\$ 8,60");
    row("Iogurte natural", "R\$ 3,50");
    row("Cereal matinal", "R\$ 13,40");
    row("Achocolatado", "R\$ 6,90");
    row("Sabão em pó", "R\$ 15,80");
    row("Amaciante roupas", "R\$ 12,70");
    row("Detergente líquido", "R\$ 2,30");
    row("Papel higiênico 12un", "R\$ 18,90");
    row("Shampoo", "R\$ 14,50");
    row("Condicionador", "R\$ 15,20");
    row("Creme dental", "R\$ 6,10");
    row("Escova de dentes", "R\$ 5,90");
    row("Sabonete", "R\$ 2,20");
    row("Água mineral 1,5L", "R\$ 2,80");
    row("Chocolate barra", "R\$ 7,50");
    row("Sorvete 2L", "R\$ 19,90");
    row("Pizza congelada", "R\$ 17,80");
    row("Hambúrguer pacote", "R\$ 13,60");
    row("Batata frita", "R\$ 9,90");
    row("Milho verde lata", "R\$ 4,10");
    row("Ervilha lata", "R\$ 4,00");
    row("Atum lata", "R\$ 8,30");
    row("Sardinha lata", "R\$ 6,70");
    row("Maionese", "R\$ 7,20");
    row("Ketchup", "R\$ 6,40");
    row("Mostarda", "R\$ 5,80");
    row("Tempero completo", "R\$ 4,90");
    row("Sal refinado", "R\$ 2,10");
    row("Pimenta molho", "R\$ 6,00");
    row("Bala sortida", "R\$ 3,20");
    row("Chiclete pacote", "R\$ 2,90");
    row("Produto ULTIMO", "R\$ 20,00");
    row("Arroz 5kg", "R\$ 28,90");
    row("Feijão carioca 1kg", "R\$ 8,50");
    row("Macarrão espaguete", "R\$ 4,20");
    row("Óleo de soja 900ml", "R\$ 7,80");
    row("Açúcar refinado 1kg", "R\$ 5,10");
    row("Café torrado 500g", "R\$ 14,90");
    row("Leite integral 1L", "R\$ 4,80");
    row("Margarina 500g", "R\$ 6,40");
    row("Farinha de trigo 1kg", "R\$ 4,60");
    row("Biscoito recheado", "R\$ 3,90");
    row("Molho de tomate", "R\$ 2,70");
    row("Refrigerante 2L", "R\$ 8,99");
    row("Suco de laranja 1L", "R\$ 6,50");
    row("Queijo muçarela 300g", "R\$ 12,80");
    row("Presunto fatiado", "R\$ 9,40");
    row("Frango congelado kg", "R\$ 11,90");
    row("Carne moída kg", "R\$ 24,90");
    row("Ovos dúzia", "R\$ 9,20");
    row("Pão de forma", "R\$ 7,30");
    row("Manteiga 200g", "R\$ 8,60");
    row("Iogurte natural", "R\$ 3,50");
    row("Cereal matinal", "R\$ 13,40");
    row("Achocolatado", "R\$ 6,90");
    row("Sabão em pó", "R\$ 15,80");
    row("Amaciante roupas", "R\$ 12,70");
    row("Detergente líquido", "R\$ 2,30");
    row("Papel higiênico 12un", "R\$ 18,90");
    row("Shampoo", "R\$ 14,50");
    row("Condicionador", "R\$ 15,20");
    row("Creme dental", "R\$ 6,10");
    row("Escova de dentes", "R\$ 5,90");
    row("Sabonete", "R\$ 2,20");
    row("Água mineral 1,5L", "R\$ 2,80");
    row("Chocolate barra", "R\$ 7,50");
    row("Sorvete 2L", "R\$ 19,90");
    row("Pizza congelada", "R\$ 17,80");
    row("Hambúrguer pacote", "R\$ 13,60");
    row("Batata frita", "R\$ 9,90");
    row("Milho verde lata", "R\$ 4,10");
    row("Ervilha lata", "R\$ 4,00");
    row("Atum lata", "R\$ 8,30");
    row("Sardinha lata", "R\$ 6,70");
    row("Maionese", "R\$ 7,20");
    row("Ketchup", "R\$ 6,40");
    row("Mostarda", "R\$ 5,80");
    row("Tempero completo", "R\$ 4,90");
    row("Sal refinado", "R\$ 2,10");
    row("Pimenta molho", "R\$ 6,00");
    row("Bala sortida", "R\$ 3,20");
    row("Chiclete pacote", "R\$ 2,90");
    row("Produto ULTIMO", "R\$ 20,00");

    add("LINE 30 160 750 160 3\r\n");
    add("BARCODE 128 1 1 50 30 400 123456789\r\n");
    add("PRINT\r\n");

    return cpcl;
  }
}


// class AutoCtbTestPrinterStrategy implements IPrinterStrategy {
//   @override
//   Future<List<int>> generateBytes(dynamic data) async {
//     final cpcl = <int>[];
//     // Helper para converter string em bytes CPCL
//     void add(String s) => cpcl.addAll(s.codeUnits);
//
//     // --- COMANDOS INICIAIS ---
//     add("\r\n");
//     add("! 0 200 200 4000 1\r\n");
//     add("PAGE-WIDTH 800\r\n");
//     add("JOURNAL\r\n"); // Modo Journal para impressão contínua
//
//     // --- FUNÇÃO AJUDANTE PARA TEXTO MULTILINHA (NO DART) ---
//     // Isso substitui o comando MULTILINE que trava a impressora.
//     // Retorna o novo Y após escrever as linhas.
//     int printMultiline(String text, int x, int startY, int maxCharsPerLine) {
//       int currentY = startY;
//       List<String> words = text.split(' ');
//       String currentLine = "";
//
//       for (var word in words) {
//         if ((currentLine + word).length > maxCharsPerLine) {
//           // Imprime a linha acumulada
//           add("T 7 0 $x $currentY $currentLine\r\n");
//           currentY += 30; // Avança 30px para baixo
//           currentLine = "";
//         }
//         currentLine += "$word ";
//       }
//       // Imprime o que sobrou
//       if (currentLine.isNotEmpty) {
//         add("T 7 0 $x $currentY $currentLine\r\n");
//         currentY += 30;
//       }
//       return currentY;
//     }
//
//     // =================================================
//     // HEADER
//     // =================================================
//     add("T 5 1 0 20 NOTIFICACAO DE AUTUACAO\r\n");
//     add("T 7 0 0 60 AUTO CTB - TESTE\r\n");
//     add("T 7 0 30 110 AIT: CTB-2026-000123\r\n");
//     add("T 7 0 30 140 DATA/HORA: 05/02/2026 10:32\r\n");
//     add("LINE 30 175 750 175 3\r\n");
//
//     // =================================================
//     // VEICULO
//     // =================================================
//     add("T 5 0 30 195 VEICULO\r\n");
//     add("T 7 0 30 230 PLACA: ABC1D23\r\n");
//     add("T 7 0 30 260 MARCA/MODELO: FIAT ARGO\r\n");
//     add("T 7 0 30 290 COR: BRANCO\r\n");
//     add("T 7 0 30 320 ANO: 2022\r\n");
//     add("LINE 30 350 750 350 3\r\n");
//
//     // =================================================
//     // CONDUTOR
//     // =================================================
//     add("T 5 0 30 370 CONDUTOR\r\n");
//     add("T 7 0 30 405 NOME: JOAO DA SILVA\r\n");
//     add("T 7 0 30 435 CNH: 12345678900\r\n");
//     add("LINE 30 465 750 465 3\r\n");
//
//     // =================================================
//     // LOCAL
//     // =================================================
//     add("T 5 0 30 485 LOCAL\r\n");
//     add("T 7 0 30 520 AV PAULISTA, 1000 - SP\r\n");
//     add("T 7 0 30 550 SENTIDO: CENTRO -> JARDINS\r\n");
//     add("LINE 30 580 750 580 3\r\n");
//
//     // =================================================
//     // INFRACAO
//     // =================================================
//     add("T 5 0 30 600 INFRACAO\r\n");
//     add("T 7 0 30 635 COD: 74550\r\n");
//     add("T 7 0 30 665 ART: 181 XVIII\r\n");
//     add("T 7 0 30 695 GRAV: MEDIA\r\n");
//
//     // SUBSTITUÍDO: MULTILINE nativo por lógica manual
//     // Texto longo da infração
//     String textoInfracao = "ESTACIONAR EM LOCAL PROIBIDO SINALIZADO";
//     // Imprime e calcula onde a linha termina (baseado em max 40 caracteres por linha)
//     int yAposInfracao = printMultiline(textoInfracao, 30, 725, 40);
//
//     // Ajustamos a linha abaixo baseada em onde o texto acabou
//     // (Ou mantemos fixa se soubermos que não vai estourar)
//     add("LINE 30 820 750 820 3\r\n");
//
//     // =================================================
//     // MEDICOES
//     // =================================================
//     add("T 5 0 30 840 MEDICOES\r\n");
//     add("T 7 0 30 875 VEL PERMITIDA: 60 KM/H\r\n");
//     add("T 7 0 30 905 VEL AFERIDA: ---\r\n");
//     add("LINE 30 935 750 935 3\r\n");
//
//     // =================================================
//     // OBSERVACOES
//     // =================================================
//     add("T 5 0 30 955 OBSERVACOES\r\n");
//
//     // SUBSTITUÍDO: MULTILINE nativo por lógica manual
//     String textoObs = "IMPRESSAO DE TESTE DO MODULO CLEAN ARCH";
//     printMultiline(textoObs, 30, 985, 40);
//
//     add("LINE 30 1080 750 1080 3\r\n");
//
//     // =================================================
//     // AGENTE
//     // =================================================
//     add("T 5 0 30 1100 AGENTE\r\n");
//     add("T 7 0 30 1135 AGENTE MARIA PEREIRA\r\n");
//     add("T 7 0 30 1165 MAT: 009988\r\n");
//
//     // =================================================
//     // 2ª VIA - INFORMACOES AO USUARIO
//     // =================================================
//     add("LINE 30 1200 750 1200 3\r\n");
//
//     // Removi CENTER/LEFT para garantir estabilidade, usando coordenada X centralizada manualmente ou 0
//     // CENTER as vezes conflita com coordenadas explícitas em alguns firmwares
//     add("T 5 0 100 1220 2a VIA - INFORMACOES AO USUARIO\r\n");
//
//     String textoLegal = "DOCUMENTO DE TESTE. CONFIRA OS DADOS IMPRESSOS.";
//     printMultiline(textoLegal, 30, 1260, 40);
//
//     // =================================================
//     // BARCODE DE TESTE
//     // =================================================
//     // Aumentei um pouco o Y para garantir que não sobreponha o texto acima
//     add("BARCODE 128 1 1 60 30 1350 CTB2026000123\r\n");
//
//     // Finaliza a impressão
//     add("PRINT\r\n");
//
//     return cpcl;
//   }
// }

// ==================== UI WIDGETS (IGUAIS) ====================

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
                  ),
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
