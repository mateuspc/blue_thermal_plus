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
-   Epson ePOS SDK transport on iOS (optional SDK install)\
-   Production tested

## 📱 Supported Platforms

  Platform   BLE   Classic   Epson ePOS
  ---------- ----- --------- -----------
  Android    ✅    ✅        ❌
  iOS        ✅    ✅ (MFi)  ✅

## 🧠 Architecture

Flutter → TransportRouter → PrinterTransportManager → (BleTransport /
ClassicTransport / EpsonEposTransport)

## 🚀 Installation

``` yaml
dependencies:
  blue_thermal_plus: ^0.1.0
```

## 📡 Basic Usage

``` dart
import 'package:blue_thermal_plus/blue_thermal_plus.dart';

final printer = BlueThermalPlus();
await printer.startScan();
await printer.connect(deviceId: deviceId);
await printer.printRawBytes(bytes);
```

## ⚙️ BLE Config Example

``` dart
await printer.configure(const PrinterConfig(
  ble: BleConfig(
    chunkSize: 200,
    chunkDelayMs: 10,
    autoDisconnectMs: 3000,
  ),
));
```

## 🧾 Epson TM-P80II on iOS

Epson printers such as `TM-P80II_001379` should use the iOS Epson ePOS SDK
transport instead of the Zebra BLE UUID transport:

``` dart
final printer = BlueThermalPlus();

await printer.configure(PrinterProfiles.epsonTmP80II);
await printer.startScan(transport: PrinterTransport.epson);
await printer.connect(
  deviceId: device.id,
  transport: PrinterTransport.epson,
);
await printer.printRawBytes(bytes, transport: PrinterTransport.epson);
```

The Epson SDK binary is not bundled in this package. Download Epson ePOS SDK for
iOS from Epson and copy `libepos2.xcframework` to:

``` text
ios/Frameworks/libepos2.xcframework
```

Then run `pod install` in the iOS app. The SDK is intentionally ignored by git
and should be supplied by the consuming app/release environment. If the printer uses Bluetooth Classic
MFi, add Epson's external accessory protocol in the app `Info.plist`:

``` xml
<key>UISupportedExternalAccessoryProtocols</key>
<array>
  <string>com.epson.escpos</string>
</array>
```

Keep `com.zebra.rawport` in the same array if your app also supports Zebra.
For BLE Epson discovery, use `EpsonPortType.bluetoothLe`; for mixed discovery,
the default profile uses `EpsonPortType.all`.

## 📢 Events

scanStarted, deviceFound, connected, ready, status, error, disconnected

## 🧪 Testing

Flutter contract tests + native core logic + real device integration.

## 👨‍💻 Author

Mateus Polonini Cardoso

## 📄 License

MIT
