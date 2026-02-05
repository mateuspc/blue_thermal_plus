## 0.0.1

### Added
- Bluetooth Low Energy (BLE) printing with automatic MTU negotiation
- Bluetooth Classic (SPP) thermal printer support on Android
- Bluetooth Classic support on iOS when supported by hardware/accessory
- Unified transport architecture (BLE + Classic)
- Real-time device discovery and connection events
- Configurable chunk size, delays and auto-disconnect
- Raw byte printing API for ESC/POS, CPCL, ZPL and custom protocols

## 0.0.2

### Updated
- General updates and improvements

## 0.0.3

### Updated
- Performance optimizations
- Small fixes and internal refactoring
- Improved reliability of Bluetooth transport layer

### 0.0.4

### Updated

- Increased Classic auto-disconnect default to improve long/large print reliability (autoDisconnectMs from 3000ms → 15000ms)
- Added chunked writing for Bluetooth Classic (configurable chunkSize + chunkDelayMs) to prevent printer buffer overflow on large payloads
- Added autoDisconnectMs=0 support to disable auto-disconnect when the app wants to manage the connection lifecycle
- Fixed
- Prevented Classic prints from being interrupted by pending auto-disconnect timers (auto-disconnect is now cancelled before/while printing and after connect)
- Improved Classic connection stability by cancelling Bluetooth discovery before RFCOMM connect (cancelDiscovery() before connect())
- Improved
- Added print concurrency guard (isPrinting) to avoid overlapping print jobs on Classic transport
- Hardened read loop against stream/IO edge cases (safer available() usage, binary logging, extra exception handling)
- Refactored Classic cleanup path into a dedicated safeClose() helper for more reliable resource release (socket/streams)




