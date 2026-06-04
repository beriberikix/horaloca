import 'dart:convert';
import 'dart:io';

/// Tiny JSON-file settings store for the handful of things horaloca needs to
/// remember between launches (currently just the chosen camera).
///
/// Deliberately dependency-free (`dart:io` only) so it needs no extra plugin.
/// The file lives under the user data dir — inside a snap, `$HOME` is already
/// redirected to `~/snap/horaloca/current`, so this stays within confinement.
class SettingsStore {
  SettingsStore({String? overridePath}) : _path = overridePath ?? _defaultPath();

  static const String _selectedCameraKey = 'selectedCameraPath';

  final String _path;
  Map<String, Object?> _data = <String, Object?>{};

  static String _defaultPath() {
    final String home =
        Platform.environment['SNAP_USER_DATA'] ?? Platform.environment['HOME'] ?? '.';
    return '$home/.config/horaloca/settings.json';
  }

  /// Load the file if present. Tolerant of missing/corrupt files (starts empty).
  Future<void> load() async {
    try {
      final File f = File(_path);
      if (await f.exists()) {
        final Object? decoded = jsonDecode(await f.readAsString());
        if (decoded is Map<String, Object?>) _data = decoded;
      }
    } catch (_) {
      _data = <String, Object?>{};
    }
  }

  /// The persisted source camera path, or null if the user never chose one.
  String? get selectedCameraPath => _data[_selectedCameraKey] as String?;

  /// Persist the chosen source camera path (best-effort; failures are ignored).
  Future<void> setSelectedCameraPath(String? path) async {
    if (path == null) {
      _data.remove(_selectedCameraKey);
    } else {
      _data[_selectedCameraKey] = path;
    }
    await _save();
  }

  Future<void> _save() async {
    try {
      final File f = File(_path);
      await f.parent.create(recursive: true);
      await f.writeAsString(jsonEncode(_data));
    } catch (_) {
      // Non-fatal: we simply won't remember the choice next launch.
    }
  }
}
