#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint blue_thermal_plus.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'blue_thermal_plus'
  s.version          = '0.1.0'
  s.summary          = 'Flutter thermal printer plugin for BLE, Classic and Epson ePOS.'
  s.description      = <<-DESC
Flutter thermal printer plugin with Android and iOS transports for BLE,
Bluetooth Classic and optional Epson ePOS SDK support on iOS.
                       DESC
  s.homepage         = 'https://bluethermalplus.web.app/'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Mateus Polonini Cardoso' => 'mateuspc@users.noreply.github.com' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'

  epson_epos_path = File.join(__dir__, 'Frameworks', 'libepos2.xcframework')
  if File.exist?(epson_epos_path)
    s.vendored_frameworks = 'Frameworks/libepos2.xcframework'
    s.preserve_paths = 'Frameworks/libepos2.xcframework'
    s.frameworks = 'CoreBluetooth', 'ExternalAccessory'
    s.libraries = 'xml2'
    s.xcconfig = {
      'HEADER_SEARCH_PATHS' => '$(inherited) "${PODS_XCFRAMEWORKS_BUILD_DIR}/blue_thermal_plus/libepos2.framework/Headers" "$(SDKROOT)/usr/include/libxml2"'
    }
  end

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'

  s.resource_bundles = {'blue_thermal_plus_privacy' => ['Resources/PrivacyInfo.xcprivacy']}
end
