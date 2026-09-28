# Optional printer SDKs

This directory is for local plugin development with proprietary printer SDKs.
Copy the framework you need here:

```text
ios/Frameworks/libepos2.xcframework
ios/Frameworks/HoneywellPrinterSDK.xcframework
ios/Frameworks/BRLMPrinterKit.xcframework
```

For apps that consume this plugin from pub, prefer placing the framework in the
app project instead:

```text
your_app/ios/Frameworks/libepos2.xcframework
your_app/ios/Frameworks/HoneywellPrinterSDK.xcframework
your_app/ios/Frameworks/BRLMPrinterKit.xcframework
```

The frameworks are intentionally not committed or published with the plugin.
Obtain each SDK from its manufacturer and accept the applicable license before
using it. Honeywell RP2f/RP4f apps must also declare `com.honeywell.print` in
`UISupportedExternalAccessoryProtocols`. Brother RJ apps must declare
`com.brother.ptcbp` in the same array.
