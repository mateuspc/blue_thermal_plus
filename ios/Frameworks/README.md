# Epson ePOS SDK

This directory is for local plugin development with Epson's ePOS SDK. Copy
Epson's `libepos2.xcframework` here when you need to test
`PrinterTransport.epson` directly from this plugin repository:

```text
ios/Frameworks/libepos2.xcframework
```

For apps that consume this plugin from pub, prefer placing the framework in the
app project instead:

```text
your_app/ios/Frameworks/libepos2.xcframework
```

The framework is intentionally not committed or published with the plugin.
Download it from Epson and accept Epson's SDK license before using it.
