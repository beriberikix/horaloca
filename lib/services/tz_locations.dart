/// Maps an IANA timezone (e.g. `Asia/Taipei`) to a friendly `"City, Country"`
/// label (e.g. `Taipei, Taiwan`) for the overlay's timezone line.
///
/// Built from the two standard IANA data files, bundled as assets:
///   * `iso3166.tab`  — `TW<TAB>Taiwan`              (country code -> name)
///   * `zone1970.tab` — `TW<TAB>+coords<TAB>Asia/Taipei[<TAB>comments]`
///                                                   (zone -> country code[s])
///
/// Pure Dart (no Flutter binding) so it is unit-testable with inline data; the
/// app loads the asset strings via `rootBundle` and passes them to [parse].
class TzLocations {
  TzLocations._(this._zoneToCountryCode, this._codeToCountry);

  final Map<String, String> _zoneToCountryCode;
  final Map<String, String> _codeToCountry;

  /// Empty resolver — [labelFor] falls back to the city alone.
  factory TzLocations.empty() =>
      TzLocations._(<String, String>{}, <String, String>{});

  /// Parse the contents of `zone1970.tab` and `iso3166.tab`.
  factory TzLocations.parse({
    required String zone1970Tab,
    required String iso3166Tab,
  }) {
    final Map<String, String> codeToCountry = <String, String>{};
    for (final String line in iso3166Tab.split('\n')) {
      if (line.isEmpty || line.startsWith('#')) continue;
      final List<String> parts = line.split('\t');
      if (parts.length >= 2) {
        codeToCountry[parts[0].trim()] = parts[1].trim();
      }
    }

    final Map<String, String> zoneToCode = <String, String>{};
    for (final String line in zone1970Tab.split('\n')) {
      if (line.isEmpty || line.startsWith('#')) continue;
      final List<String> parts = line.split('\t');
      if (parts.length < 3) continue;
      // A zone may be shared by several countries (comma-separated codes); the
      // first is the canonical/primary one.
      final String code = parts[0].split(',').first.trim();
      final String zone = parts[2].trim();
      if (zone.isNotEmpty) zoneToCode[zone] = code;
    }

    return TzLocations._(zoneToCode, codeToCountry);
  }

  /// `"Taipei, Taiwan"`, or just `"Taipei"` when the country can't be resolved.
  /// Returns `null` only for an empty zone.
  String? labelFor(String ianaZone) {
    if (ianaZone.isEmpty) return null;
    final String city = _cityOf(ianaZone);
    final String? code = _zoneToCountryCode[ianaZone];
    final String? country = code == null ? null : _codeToCountry[code];
    if (country == null || country.isEmpty) return city;
    return '$city, $country';
  }

  /// City = the zone's last `/` segment with underscores turned into spaces,
  /// e.g. `America/Argentina/Buenos_Aires` -> `Buenos Aires`.
  static String _cityOf(String zone) {
    final String last = zone.contains('/') ? zone.split('/').last : zone;
    return last.replaceAll('_', ' ');
  }
}
