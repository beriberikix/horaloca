import 'dart:async';
import 'dart:io';

import 'package:intl/intl.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'tz_locations.dart';

/// Produces the formatted local-time string that gets burned into the video,
/// and tracks the host's current timezone.
///
/// Responsibilities (single source of truth for "what time is it"):
///   * Resolve the host IANA timezone (e.g. `America/Los_Angeles`) from the OS.
///   * Emit a formatted string every second on [timeStream].
///   * Re-resolve the zone on demand via [refreshTimezone] (tray action), so
///     travelling / `timedatectl set-timezone` is picked up without a restart.
///
/// Formatting honours a 12h/24h flag. Output examples:
///   * 12h: `03:45 AM (PST)`
///   * 24h: `16:20 (CEST)`
///
/// This class is pure Dart + OS reads — no hardware, no platform channel — so
/// it is fully unit-testable (see test/clock_service_test.dart).
class ClockService {
  ClockService({this.use24HourClock = false, TzLocations? locations})
      : _locations = locations ?? TzLocations.empty() {
    // Load the bundled IANA database once. Safe to call repeatedly.
    tzdata.initializeTimeZones();
    _location = _resolveLocation();
  }

  /// Resolves IANA zone -> "City, Country" for the timezone line. Injected so
  /// the asset-loading stays out of this Flutter-binding-free class.
  final TzLocations _locations;

  /// Path to the symlink Ubuntu/systemd maintains pointing at the active zone
  /// file under the zoneinfo tree. Reading its target yields the IANA name.
  static const String _localtimeLink = '/etc/localtime';

  /// Common prefix of the zoneinfo tree the symlink points into.
  static const String _zoneinfoMarker = '/zoneinfo/';

  bool use24HourClock;

  late tz.Location _location;

  final StreamController<String> _controller = StreamController<String>.broadcast();
  Timer? _timer;
  String? _lastEmitted;

  /// Broadcast stream of formatted time strings, one per tick (deduplicated:
  /// only emits when the rendered string actually changes).
  Stream<String> get timeStream => _controller.stream;

  /// The currently resolved IANA timezone name, e.g. `Europe/Berlin`.
  String get timezoneName => _location.name;

  /// Start ticking. Emits the current value immediately, then every second.
  void start() {
    if (_timer != null) return;
    _emit(); // immediate first value so the overlay is never blank
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _emit());
  }

  /// Stop ticking (does not close the stream; call [dispose] for that).
  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Re-read the host timezone. Returns the new IANA name. If it changed, the
  /// next tick (and an immediate emit) reflect it.
  String refreshTimezone() {
    _location = _resolveLocation();
    _lastEmitted = null; // force a re-emit even if the minute didn't change
    if (_timer != null) _emit();
    return _location.name;
  }

  /// The current formatted string, computed on demand (used for tests and for
  /// seeding the overlay before [start]).
  String currentFormatted() {
    final tz.TZDateTime now = tz.TZDateTime.now(_location);
    return format(now);
  }

  /// Pure formatter, separated out so tests can pin a specific instant/zone.
  ///
  /// Produces two stacked lines — time on top, the full timezone line below:
  ///
  ///   11:35 AM
  ///   CST (Taipei, Taiwan)
  ///
  /// The abbreviation now lives on the second line; the location is resolved
  /// from the IANA zone via [TzLocations], falling back to the raw zone name.
  String format(tz.TZDateTime now) {
    final String time = use24HourClock
        ? DateFormat('HH:mm').format(now)
        : DateFormat('hh:mm a').format(now);
    final String abbreviation = now.timeZone.abbreviation;
    final String location = _locations.labelFor(now.location.name) ??
        now.location.name; // e.g. "Taipei, Taiwan"
    return '$time\n$abbreviation ($location)';
  }

  void _emit() {
    final String value = currentFormatted();
    if (value == _lastEmitted) return;
    _lastEmitted = value;
    _controller.add(value);
  }

  /// Resolve the active [tz.Location] from the OS, with graceful fallbacks:
  ///   1. The `TZ` environment variable (respected by systemd/containers).
  ///   2. The `/etc/localtime` symlink target (the normal Ubuntu case).
  ///   3. UTC, if neither is resolvable.
  tz.Location _resolveLocation() {
    final String? name = _resolveTimezoneName();
    if (name != null) {
      try {
        return tz.getLocation(name);
      } catch (_) {
        // Unknown/badly-formed name — fall through to UTC.
      }
    }
    return tz.getLocation('UTC');
  }

  /// Best-effort extraction of the IANA timezone name from the host.
  /// Public-ish via [refreshTimezone]; exposed as a static helper-shaped method
  /// to keep the resolution logic in one place.
  String? _resolveTimezoneName() {
    final String? envTz = Platform.environment['TZ'];
    if (envTz != null && envTz.isNotEmpty) return envTz;

    try {
      final Link link = Link(_localtimeLink);
      if (link.existsSync()) {
        final String target = link.targetSync();
        final int idx = target.indexOf(_zoneinfoMarker);
        if (idx != -1) {
          return target.substring(idx + _zoneinfoMarker.length);
        }
      }
      // Some systems make /etc/localtime a copy, not a symlink; fall back to
      // the systemd-maintained /etc/timezone file if present.
      final File tzFile = File('/etc/timezone');
      if (tzFile.existsSync()) {
        final String content = tzFile.readAsStringSync().trim();
        if (content.isNotEmpty) return content;
      }
    } catch (_) {
      // Sandboxed / permission denied — fall back to UTC upstream.
    }
    return null;
  }

  Future<void> dispose() async {
    stop();
    await _controller.close();
  }
}
