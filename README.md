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
-   Honeywell RP2f/RP4f PrinterSDK routing on iOS (optional SDK install)\
-   Brother Print SDK routing on Android and iOS (optional SDK install)\
-   Production tested

## 📱 Supported Platforms

| Platform | BLE | Classic | Brother Print SDK | Honeywell PrinterSDK | Epson ePOS |
| --- | --- | --- | --- | --- | --- |
| Android | ✅ | ✅ | ✅ | Native Classic path | ❌ |
| iOS | ✅ | ✅ (MFi) | ✅ | ✅ | ✅ |

## 🧠 Architecture

Flutter → TransportRouter → PrinterTransportManager → (BleTransport /
ClassicTransport / Brother Print SDK bridge / HoneywellPrinterSDK bridge /
EpsonEposTransport)

## 🚀 Installation

``` yaml
dependencies:
  blue_thermal_plus: ^0.1.3
```

Then run:

``` sh
flutter pub get
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

The Epson SDK binary is not bundled or published with this package. Download
Epson ePOS SDK for iOS from Epson and copy `libepos2.xcframework` to the
consuming app:

``` text
your_app/ios/Frameworks/libepos2.xcframework
```

If you are developing this plugin locally, you can also place it in:

``` text
blue_thermal_plus/ios/Frameworks/libepos2.xcframework
```

Then run `pod install` in the iOS app:

``` sh
cd ios
pod install
```

If the printer uses Bluetooth Classic MFi, add Epson's external accessory
protocol in the app `Info.plist`:

``` xml
<key>UISupportedExternalAccessoryProtocols</key>
<array>
  <string>com.epson.escpos</string>
</array>
```

Keep `com.zebra.rawport` in the same array if your app also supports Zebra.
For BLE Epson discovery, use `EpsonPortType.bluetoothLe`; for mixed discovery,
the default profile uses `EpsonPortType.all`.

For TCP discovery/printing on iOS, your app may also need the local network
privacy keys used by iOS 14+:

``` xml
<key>NSLocalNetworkUsageDescription</key>
<string>This app uses the local network to discover and connect to printers.</string>
```

If the Epson SDK is missing, `PrinterTransport.epson` remains available but
emits an `error` event explaining that `libepos2.xcframework` was not found.

## 🧾 Honeywell RP2f/RP4f on iOS

Honeywell RP2f/RP4f printers remain on `PrinterTransport.classic`. When the
paired accessory announces `com.honeywell.print` and the official SDK is
installed, the plugin automatically routes connect/write/disconnect through
`Connection_BluetoothEA`. No Honeywell-specific Dart transport is required.

Use the explicit RP4f profile before scanning and connecting:

```dart
final printer = BlueThermalPlus();

await printer.configure(PrinterProfiles.honeywellRp4f);
await printer.startScan(transport: PrinterTransport.classic);
await printer.connect(
  deviceId: device.id,
  transport: PrinterTransport.classic,
);
await printer.printRawBytes(bytes, transport: PrinterTransport.classic);
```

The Honeywell binary is not bundled or published with this package. Copy the
official `HoneywellPrinterSDK.xcframework` to the consuming app:

```text
your_app/ios/Frameworks/HoneywellPrinterSDK.xcframework
```

Because CocoaPods requires vendored frameworks to be relative to the plugin,
call the package installer after `flutter_install_all_ios_pods` in the app
`Podfile`:

```ruby
target 'Runner' do
  use_frameworks!
  flutter_install_all_ios_pods File.dirname(File.realpath(__FILE__))

  plugin_ios_dir = File.expand_path(
    File.join(__dir__, '.symlinks', 'plugins', 'blue_thermal_plus', 'ios')
  )
  require File.join(plugin_ios_dir, 'prepare_optional_sdks.rb')
  BlueThermalPlusSdkInstaller.prepare(
    app_ios_dir: __dir__,
    plugin_ios_dir: plugin_ios_dir,
  )
end
```

Add the protocol to the app `Info.plist`, preserving any Zebra/Epson entries:

```xml
<key>UISupportedExternalAccessoryProtocols</key>
<array>
  <string>com.zebra.rawport</string>
  <string>com.epson.escpos</string>
  <string>com.honeywell.print</string>
</array>
```

Honeywell PrinterSDK 3.1.109 requires iOS 15.2 or newer. Without the SDK, the
plugin keeps a direct `EASession` fallback for `com.honeywell.print`.

## 🧾 Brother RJ-4235B

Brother printers remain on `PrinterTransport.classic`. Select the explicit
profile so the native layer uses Brother's SDK while keeping the raw CPCL byte
payload unchanged:

```dart
final printer = BlueThermalPlus();

await printer.configure(PrinterProfiles.brotherRj4235B);
await printer.startScan(transport: PrinterTransport.classic);
await printer.connect(
  deviceId: device.id,
  transport: PrinterTransport.classic,
);
await printer.printRawBytes(bytes, transport: PrinterTransport.classic);
```

The proprietary SDK binaries are intentionally not included in this package.
Download Brother Print SDK 4.13.2 (or a compatible version accepted under
Brother's license), then place the files in the consuming app:

```text
your_app/android/Frameworks/BrotherPrintLibrary.aar
your_app/ios/Frameworks/BRLMPrinterKit.xcframework
```

Use the same `Podfile` installer shown above for iOS and add Brother's MFi
protocol to the app `Info.plist`:

```xml
<key>UISupportedExternalAccessoryProtocols</key>
<array>
  <string>com.brother.ptcbp</string>
</array>
```

The Android integration loads the AAR from the host app without making the
proprietary SDK a required plugin dependency. Add it to the host application's
Gradle dependencies (Kotlin DSL example):

```kotlin
dependencies {
  implementation(files("../Frameworks/BrotherPrintLibrary.aar"))
}
```

On iOS, the bridge requires iOS 14 or newer and reports an explicit error when
the framework is absent.

## 📢 Events

scanStarted, deviceFound, connected, ready, status, error, disconnected

## 🧪 Testing

Flutter contract tests + native core logic + real device integration.

## 👨‍💻 Author

Mateus Polonini Cardoso

## 📄 License

MIT
