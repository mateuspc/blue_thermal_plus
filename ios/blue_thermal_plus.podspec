#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint blue_thermal_plus.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'blue_thermal_plus'
  s.version          = '0.2.0'
  s.summary          = 'Flutter thermal printer plugin for BLE, Classic, Brother, Honeywell and Epson ePOS.'
  s.description      = <<-DESC
Flutter thermal printer plugin with Android and iOS transports for BLE,
Bluetooth Classic, optional Brother Print SDK, optional Honeywell PrinterSDK
and optional Epson ePOS SDK support on iOS.
                       DESC
  s.homepage         = 'https://bluethermalplus.web.app/'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Mateus Polonini Cardoso' => 'mateuspc@users.noreply.github.com' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'

  vendored_frameworks = []

  epson_epos_relative_path = 'Frameworks/libepos2.xcframework'
  epson_epos_plugin_path = File.join(__dir__, epson_epos_relative_path)
  epson_epos_path = epson_epos_relative_path if File.exist?(epson_epos_plugin_path)

  if epson_epos_path
    vendored_frameworks << epson_epos_path
    s.libraries = 'xml2'
    s.xcconfig = {
      'HEADER_SEARCH_PATHS' => '$(inherited) "${PODS_XCFRAMEWORKS_BUILD_DIR}/blue_thermal_plus/libepos2.framework/Headers" "$(SDKROOT)/usr/include/libxml2"'
    }
  end

  honeywell_relative_path = 'Frameworks/HoneywellPrinterSDK.xcframework'
  honeywell_plugin_path = File.join(__dir__, honeywell_relative_path)
  honeywell_path = honeywell_relative_path if File.exist?(honeywell_plugin_path)

  if honeywell_path
    vendored_frameworks << honeywell_path
    # HoneywellPrinterSDK 3.1.109 declares iOS 15.2 as its binary minimum.
    s.ios.deployment_target = '15.2'
  end

  brother_relative_path = 'Frameworks/BRLMPrinterKit.xcframework'
  brother_plugin_path = File.join(__dir__, brother_relative_path)
  brother_path = brother_relative_path if File.exist?(brother_plugin_path)

  if brother_path
    vendored_frameworks << brother_path
    # Brother Print SDK 4.13.2 declares iOS 14 as its binary minimum.
    s.ios.deployment_target = honeywell_path ? '15.2' : '14.0'
  end

  unless vendored_frameworks.empty?
    s.vendored_frameworks = vendored_frameworks
    s.preserve_paths = vendored_frameworks
  end

  s.frameworks = 'CoreBluetooth', 'ExternalAccessory'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'

  s.resource_bundles = {'blue_thermal_plus_privacy' => ['Resources/PrivacyInfo.xcprivacy']}
end
