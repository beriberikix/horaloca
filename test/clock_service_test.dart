import 'package:flutter_test/flutter_test.dart';
import 'package:horaloca/services/clock_service.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

void main() {
  setUpAll(() {
    // ClockService initialises the DB too, but tests construct TZDateTime
    // directly so make sure the DB is loaded.
    tzdata.initializeTimeZones();
  });

  group('ClockService.format', () {
    test('12-hour format produces "hh:mm AM/PM (ABBR)"', () {
      final ClockService clock = ClockService(use24HourClock: false);
      final tz.Location la = tz.getLocation('America/Los_Angeles');
      // 03:45 local, winter -> PST.
      final tz.TZDateTime t = tz.TZDateTime(la, 2025, 1, 15, 3, 45);
      expect(clock.format(t), '03:45 AM (PST)');
    });

    test('12-hour format handles afternoon as PM', () {
      final ClockService clock = ClockService(use24HourClock: false);
      final tz.Location la = tz.getLocation('America/Los_Angeles');
      final tz.TZDateTime t = tz.TZDateTime(la, 2025, 1, 15, 16, 20);
      expect(clock.format(t), '04:20 PM (PST)');
    });

    test('24-hour format produces "HH:mm (ABBR)"', () {
      final ClockService clock = ClockService(use24HourClock: true);
      final tz.Location berlin = tz.getLocation('Europe/Berlin');
      // Summer -> CEST.
      final tz.TZDateTime t = tz.TZDateTime(berlin, 2025, 7, 1, 16, 20);
      expect(clock.format(t), '16:20 (CEST)');
    });

    test('reflects daylight-saving abbreviation changes', () {
      final ClockService clock = ClockService(use24HourClock: true);
      final tz.Location la = tz.getLocation('America/Los_Angeles');
      final tz.TZDateTime winter = tz.TZDateTime(la, 2025, 1, 1, 12, 0);
      final tz.TZDateTime summer = tz.TZDateTime(la, 2025, 7, 1, 12, 0);
      expect(clock.format(winter), endsWith('(PST)'));
      expect(clock.format(summer), endsWith('(PDT)'));
    });
  });

  group('ClockService timezone resolution', () {
    test('exposes a non-empty timezone name', () {
      final ClockService clock = ClockService();
      expect(clock.timezoneName, isNotEmpty);
    });

    test('refreshTimezone returns a resolvable name', () {
      final ClockService clock = ClockService();
      final String name = clock.refreshTimezone();
      expect(() => tz.getLocation(name), returnsNormally);
    });
  });
}
