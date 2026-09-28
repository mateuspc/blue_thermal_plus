# frozen_string_literal: true

require 'fileutils'

module BlueThermalPlusSdkInstaller
  OPTIONAL_SDKS = [
    'libepos2.xcframework',
    'HoneywellPrinterSDK.xcframework',
    'BRLMPrinterKit.xcframework',
  ].freeze

  def self.prepare(app_ios_dir:, plugin_ios_dir:)
    plugin_podspec_path = File.join(plugin_ios_dir, 'blue_thermal_plus.podspec')
    unless File.exist?(plugin_podspec_path)
      puts '  [WARN] Podspec do blue_thermal_plus nao encontrado. Rode flutter pub get antes do pod install.'
      return false
    end

    OPTIONAL_SDKS.each do |sdk_name|
      app_sdk_path = File.expand_path(File.join(app_ios_dir, 'Frameworks', sdk_name))
      plugin_sdk_path = File.join(plugin_ios_dir, 'Frameworks', sdk_name)

      unless File.exist?(app_sdk_path)
        puts "  [WARN] SDK opcional nao encontrado em #{app_sdk_path}"
        next
      end

      FileUtils.rm_rf(plugin_sdk_path)
      FileUtils.mkdir_p(File.dirname(plugin_sdk_path))
      FileUtils.cp_r(app_sdk_path, plugin_sdk_path)
      puts "  [OK] #{sdk_name} preparado para blue_thermal_plus"
    end

    true
  end
end
