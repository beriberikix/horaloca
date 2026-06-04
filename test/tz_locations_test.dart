import 'package:flutter_test/flutter_test.dart';
import 'package:horaloca/services/tz_locations.dart';

void main() {
  // Minimal samples mirroring the real IANA tab file formats (tab-separated).
  const String iso3166 = '#code\tname\n'
      'TW\tTaiwan\n'
      'US\tUnited States\n'
      'DE\tGermany\n';
  const String zone1970 = '#codes\tcoordinates\tTZ\tcomments\n'
      'TW\t+2503+12130\tAsia/Taipei\n'
      'US\t+404251-0740023\tAmerica/New_York\tEastern (most areas)\n'
      'DE\t+5230+01322\tEurope/Berlin\n'
      'AR\t-3436-05827\tAmerica/Argentina/Buenos_Aires\n';

  final TzLocations tz =
      TzLocations.parse(zone1970Tab: zone1970, iso3166Tab: iso3166);

  test('maps zone to City, Country', () {
    expect(tz.labelFor('Asia/Taipei'), 'Taipei, Taiwan');
    expect(tz.labelFor('America/New_York'), 'New York, United States');
  });

  test('multi-segment zone uses last segment as city', () {
    // AR is present in zone1970 but not iso3166 -> country unknown -> city only.
    expect(tz.labelFor('America/Argentina/Buenos_Aires'), 'Buenos Aires');
  });

  test('unknown zone falls back to city alone', () {
    expect(tz.labelFor('Atlantis/Lost_City'), 'Lost City');
  });

  test('empty zone returns null', () {
    expect(tz.labelFor(''), isNull);
  });

  test('empty resolver returns city only', () {
    final TzLocations empty = TzLocations.empty();
    expect(empty.labelFor('Asia/Taipei'), 'Taipei');
  });
}
