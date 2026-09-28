import 'package:blue_thermal_plus/blue_thermal_plus.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Honeywell RP4f profile selects the Honeywell accessory protocol', () {
    const profile = PrinterProfiles.honeywellRp4f;

    expect(profile.classic.preferredProtocol, 'com.honeywell.print');
    expect(profile.classic.autoDisconnectMs, 0);
    expect(profile.classic.backend, ClassicPrinterBackend.honeywell);
    expect(
      profile.toMap()['classic'],
      containsPair('preferredProtocol', 'com.honeywell.print'),
    );
  });

  test('Brother RJ-4235B profile selects the official SDK backend', () {
    const profile = PrinterProfiles.brotherRj4235B;

    expect(profile.classic.preferredProtocol, 'com.brother.ptcbp');
    expect(profile.classic.autoDisconnectMs, 0);
    expect(profile.classic.backend, ClassicPrinterBackend.brother);
    expect(profile.toMap()['classic'], containsPair('backend', 'brother'));
  });

  test('Classic defaults preserve the generic backend', () {
    const config = ClassicConfig();

    expect(config.backend, ClassicPrinterBackend.generic);
    expect(config.toMap()['backend'], 'generic');
  });
}
