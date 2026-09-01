# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'

require_relative '../prepare_optional_sdks'

class PrepareOptionalSdksTest < Minitest::Test
  def test_copies_available_frameworks_into_plugin
    Dir.mktmpdir do |root|
      app_ios_dir = File.join(root, 'app', 'ios')
      plugin_ios_dir = File.join(root, 'plugin', 'ios')
      FileUtils.mkdir_p(File.join(app_ios_dir, 'Frameworks', 'HoneywellPrinterSDK.xcframework'))
      FileUtils.mkdir_p(File.join(app_ios_dir, 'Frameworks', 'libepos2.xcframework'))
      FileUtils.mkdir_p(plugin_ios_dir)
      FileUtils.touch(File.join(plugin_ios_dir, 'blue_thermal_plus.podspec'))
      FileUtils.touch(
        File.join(app_ios_dir, 'Frameworks', 'HoneywellPrinterSDK.xcframework', 'Info.plist')
      )

      result = BlueThermalPlusSdkInstaller.prepare(
        app_ios_dir: app_ios_dir,
        plugin_ios_dir: plugin_ios_dir,
      )

      assert result
      assert File.exist?(
        File.join(plugin_ios_dir, 'Frameworks', 'HoneywellPrinterSDK.xcframework', 'Info.plist')
      )
      assert Dir.exist?(File.join(plugin_ios_dir, 'Frameworks', 'libepos2.xcframework'))
    end
  end

  def test_returns_false_when_plugin_podspec_is_missing
    Dir.mktmpdir do |root|
      refute BlueThermalPlusSdkInstaller.prepare(
        app_ios_dir: File.join(root, 'app', 'ios'),
        plugin_ios_dir: File.join(root, 'plugin', 'ios'),
      )
    end
  end
end
