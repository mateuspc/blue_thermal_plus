# 📦 BlueThermal Plus --- Flutter Bluetooth Thermal Printer Plugin

A high-performance Flutter plugin for printing to thermal printers over
**Bluetooth Low Energy (BLE)** and **Bluetooth Classic (SPP)** on
**Android and iOS**.

Built with a clean transport-layer architecture for reliability,
scalability, and production-grade stability.

## ✨ Features

-   BLE printing with MTU-aware chunking\
-   Bluetooth Classic (SPP) support\
-   Automatic MTU negotiation\
-   Smart data chunking & retry system\
-   Auto-disconnect after print\
-   Real-time device discovery events\
-   Unified transport interface\
-   Production tested

## 📱 Supported Platforms

  Platform   BLE   Classic
  ---------- ----- ---------------
  Android    ✅    ✅
  iOS        ✅    ✅ (MFi)

## 🧠 Architecture

Flutter → TransportRouter → PrinterTransportManager → (BleTransport /
ClassicTransport)

## 🚀 Installation

``` yaml
dependencies:
  blue_thermal_plus: ^1.0.0
```

## 📡 Basic Usage

``` dart
final printer = BlueThermalPlus();
printer.startScan();
printer.connect(deviceId);
printer.printRaw(bytes);
```

## ⚙️ BLE Config Example

``` dart
printer.configure({
  "chunkSize": 200,
  "chunkDelayMs": 10,
  "autoDisconnectMs": 3000
});
```

## 📢 Events

scanStarted, deviceFound, connected, ready, status, error, disconnected

## 🧪 Testing

Flutter contract tests + native core logic + real device integration.

## 👨‍💻 Author

Mateus Polonini Cardoso

## 📄 License

MIT
