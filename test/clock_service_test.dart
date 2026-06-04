import 'package:flutter_test/flutter_test.dart';
import 'package:horaloca/services/clock_service.dart';
import 'package:horaloca/services/tz_locations.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

void main() {
  setUpAll(tzdata.initializeTimeZones);

  // Sample tz data so format() can resolve "City, Country".
  final TzLocations locations = TzLocations.parse(
    iso3166Tab: 'US\tUnited States\nDE\tGermany\n',
    zone1970Tab: 'US\t+0\tAmerica/Los_Angeles\n'
        'DE\t+0\tEurope/Berlin\n',
  );

  group('ClockService.format (stacked two-line)', () {
    test('12-hour: time on top, abbreviation + City, Country below', () {
      final ClockService clock =
          ClockService(use24HourClock: false, locations: locations);
      final tz.Location la = tz.getLocation('America/Los_Angeles');
      final tz.TZDateTime t = tz.TZDateTime(la, 2025, 1, 15, 3, 45);
      expect(clock.format(t), '03:45 AM\nPST (Los Angeles, United States)');
    });

    test('12-hour afternoon is PM', () {
      final ClockService clock =
          ClockService(use24HourClock: false, locations: locations);
      final tz.Location la = tz.getLocation('America/Los_Angeles');
      final tz.TZDateTime t = tz.TZDateTime(la, 2025, 1, 15, 16, 20);
      expect(clock.format(t), '04:20 PM\nPST (Los Angeles, United States)');
    });

    test('24-hour: Europe/Berlin summer is CEST', () {
      final ClockService clock =
          ClockService(use24HourClock: true, locations: locations);
      final tz.Location berlin = tz.getLocation('Europe/Berlin');
      final tz.TZDateTime t = tz.TZDateTime(berlin, 2025, 7, 1, 16, 20);
      expect(clock.format(t), '16:20\nCEST (Berlin, Germany)');
    });

    test('reflects daylight-saving abbreviation changes', () {
      final ClockService clock =
          ClockService(use24HourClock: true, locations: locations);
      final tz.Location la = tz.getLocation('America/Los_Angeles');
      expect(clock.format(tz.TZDateTime(la, 2025, 1, 1, 12)),
          contains('PST ('));
      expect(clock.format(tz.TZDateTime(la, 2025, 7, 1, 12)),
          contains('PDT ('));
    });

    test('falls back to the raw zone name without tz data', () {
      final ClockService clock = ClockService(use24HourClock: true);
      final tz.Location la = tz.getLocation('America/Los_Angeles');
      // City-only fallback (empty resolver) -> "Los Angeles".
      expect(clock.format(tz.TZDateTime(la, 2025, 1, 1, 12)),
          '12:00\nPST (Los Angeles)');
    });
  });

  group('ClockService timezone resolution', () {
    test('exposes a non-empty timezone name', () {
      expect(ClockService().timezoneName, isNotEmpty);
    });

    test('refreshTimezone returns a resolvable name', () {
      final ClockService clock = ClockService();
      expect(() => tz.getLocation(clock.refreshTimezone()), returnsNormally);
    });
  });
}
