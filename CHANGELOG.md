## 0.1.0

### Added
- Added optional Epson ePOS SDK transport on iOS via `PrinterTransport.epson`.
- Added Epson TM-P80II profile with `PrinterProfiles.epsonTmP80II`.
- Added public `blue_thermal_plus.dart` barrel export for package consumers.
- Added iOS Epson SDK framework placeholder and documentation for `libepos2.xcframework`.

### Updated
- Updated project Flutter SDK pin to 3.41.9.
- Updated iOS example project through Flutter's UIScene migration.
- Updated example app to select between BLE, Classic and Epson ePOS transports.
- Aligned iOS podspec metadata and version with the Dart package.

### Fixed
- Kept Zebra BLE and Classic paths unchanged while routing Epson printers through ePOS.
- Added Android fallback messaging for unsupported Epson ePOS transport.

## 0.0.4

### Updated
- Increased Classic auto-disconnect default to improve long/large print reliability (autoDisconnectMs from 3000ms → 15000ms)
- Added chunked writing for Bluetooth Classic (configurable chunkSize + chunkDelayMs) to prevent printer buffer overflow on large payloads
- Added autoDisconnectMs=0 support to disable auto-disconnect when the app wants to manage the connection lifecycle

### Fixed
- Prevented Classic prints from being interrupted by pending auto-disconnect timers (auto-disconnect is now cancelled before/while printing and after connect)
- Improved Classic connection stability by cancelling Bluetooth discovery before RFCOMM connect (cancelDiscovery() before connect())
- Added print concurrency guard (isPrinting) to avoid overlapping print jobs on Classic transport
- Hardened read loop against stream/IO edge cases (safer available() usage, binary logging, extra exception handling)
- Refactored Classic cleanup path into a dedicated safeClose() helper for more reliable resource release (socket/streams)

## 0.0.3

### Updated
- Performance optimizations
- Small fixes and internal refactoring
- Improved reliability of Bluetooth transport layer

## 0.0.2

### Updated
- General updates and improvements

## 0.0.1

### Added
- Bluetooth Low Energy (BLE) printing with automatic MTU negotiation
- Bluetooth Classic (SPP) thermal printer support on Android
- Bluetooth Classic support on iOS when supported by hardware/accessory
- Unified transport architecture (BLE + Classic)
- Real-time device discovery and connection events
- Configurable chunk size, delays and auto-disconnect
- Raw byte printing API for ESC/POS, CPCL, ZPL and custom protocols
