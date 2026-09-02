import 'package:blue_thermal_plus/blue_thermal_plus.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Honeywell RP4f profile selects the Honeywell accessory protocol', () {
    const profile = PrinterProfiles.honeywellRp4f;

    expect(profile.classic.preferredProtocol, 'com.honeywell.print');
    expect(profile.classic.autoDisconnectMs, 0);
    expect(
      profile.toMap()['classic'],
      containsPair('preferredProtocol', 'com.honeywell.print'),
    );
  });
}
