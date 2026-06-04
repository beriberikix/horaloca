import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/overlay_config.dart';
import '../services/clock_service.dart';
import '../services/settings_store.dart';
import '../services/tray_service.dart';
import '../services/video_pipeline_bridge.dart';
import 'app_state.dart';

/// The central coordinator: owns the [OverlayConfig] and [AppState], and wires
/// the clock, the tray, and the native video pipeline together.
///
/// This is the single seam every interaction flows through:
///   * ClockService tick   → updateOverlay(text)            → native renderer
///   * Tray "Status" click  → start()/stop()                → native pipeline
///   * Tray "Camera ▸"      → selectCamera(path) + restart  → native pipeline
///   * Tray "Refresh TZ"    → clock.refreshTimezone()       → state + overlay
///   * (Phase 2) settings   → updateConfig(position/font/…) → native renderer
///
/// It extends [ChangeNotifier] so the (future) settings window can rebuild from
/// it; the tray is updated explicitly because it lives outside the widget tree.
class AppController extends ChangeNotifier {
  AppController({
    required ClockService clock,
    required VideoPipelineBridge bridge,
    required SettingsStore settings,
    required TrayService Function(TrayCallbacks) trayFactory,
  })  : _clock = clock,
        _bridge = bridge,
        _settings = settings {
    _tray = trayFactory(
      TrayCallbacks(
        onToggleRunning: toggleRunning,
        onRefreshTimezone: refreshTimezone,
        onSelectCamera: selectCamera,
        onQuit: quit,
      ),
    );
  }

  final ClockService _clock;
  final VideoPipelineBridge _bridge;
  final SettingsStore _settings;
  late final TrayService _tray;

  AppState _state = const AppState();
  AppState get state => _state;

  OverlayConfig _config = const OverlayConfig();
  OverlayConfig get config => _config;

  /// Cached non-loopback cameras, for the tray "Camera" submenu.
  List<CameraDevice> _cameras = const <CameraDevice>[];
  List<CameraDevice> get cameras => _cameras;

  /// The user's explicit camera override (persisted), or null to auto-pick.
  String? _selectedPath;

  /// The device the pipeline is actually using right now (for the menu check).
  String? _activeInputPath;
  String? get activeInputPath => _activeInputPath;

  StreamSubscription<String>? _clockSub;
  StreamSubscription<({PipelineStatus status, String? error})>? _statusSub;

  /// Bring the app up: load settings, enumerate cameras, init the tray, then
  /// auto-start the pipeline so it works the moment the user opens a call.
  Future<void> initialize({bool autoStart = true}) async {
    await _settings.load();
    _selectedPath = _settings.selectedCameraPath;

    _state = _state.copyWith(timezoneName: _clock.timezoneName);
    _config = _config.copyWith(text: _clock.currentFormatted());

    // Enumerate cameras up front so the tray menu is populated immediately.
    await _refreshDevices();

    // The tray is cosmetic relative to the core job (running the video
    // pipeline). Never let a tray backend quirk abort startup — if init fails,
    // log and carry on so auto-start still happens.
    try {
      await _tray.init(_state, cameras: _cameras, selectedPath: _menuSelection());
    } catch (e) {
      debugPrint('horaloca: tray init failed (continuing): $e');
    }

    // Native lifecycle → our state → tray.
    _statusSub = _bridge.statusStream.listen(_onNativeStatus);

    // Clock ticks → overlay text.
    _clock.start();
    _clockSub = _clock.timeStream.listen(_onTick);

    if (autoStart) {
      await startPipeline();
    } else {
      await _refreshTray();
    }
  }

  /// Pull the current device list from native and cache the cameras.
  Future<void> _refreshDevices() async {
    try {
      final List<CameraDevice> all = await _bridge.listDevices();
      _cameras =
          all.where((CameraDevice d) => !d.isLoopback).toList(growable: false);
      debugPrint('horaloca: cameras = '
          '${_cameras.map((c) => '${c.path}(color=${c.isColor})').join(', ')}');
    } catch (e) {
      debugPrint('horaloca: listDevices failed: $e');
      _cameras = const <CameraDevice>[];
    }
  }

  /// Choose the input camera, in priority order:
  ///   1. the user's explicit pick, if still present;
  ///   2. the first confirmed *colour* camera;
  ///   3. the first *non-mono* camera (unknown classification — e.g. a cam whose
  ///      formats we couldn't enumerate in-snap; cameras are listed lowest /dev
  ///      number first, which is almost always the primary RGB cam);
  ///   4. anything (last resort, even a mono/IR sensor).
  /// This keeps us off the greyscale IR camera however the probe behaves.
  CameraDevice? _chooseInput() {
    if (_cameras.isEmpty) return null;
    if (_selectedPath != null) {
      for (final CameraDevice c in _cameras) {
        if (c.path == _selectedPath) return c;
      }
    }
    for (final CameraDevice c in _cameras) {
      if (c.isColor) return c;
    }
    for (final CameraDevice c in _cameras) {
      if (!c.isMono) return c;
    }
    return _cameras.first;
  }

  /// What the menu should show as checked (the active device, falling back to
  /// the would-be default when stopped).
  String? _menuSelection() => _activeInputPath ?? _chooseInput()?.path;

  Future<void> _onTick(String formatted) async {
    _config = _config.copyWith(text: formatted);
    if (_state.isRunning) {
      // Fire-and-forget; a dropped tick just means the next second corrects it.
      unawaited(_bridge.updateOverlay(_config));
    }
    notifyListeners();
  }

  void _onNativeStatus(({PipelineStatus status, String? error}) event) {
    _state = _state.copyWith(
      status: event.status,
      errorMessage: event.error,
      clearError: event.error == null,
    );
    unawaited(_refreshTray());
    notifyListeners();
  }

  /// Start the physical→virtual pipeline using the chosen colour camera.
  Future<void> startPipeline() async {
    _setStatus(PipelineStatus.starting);
    try {
      await _refreshDevices();

      final CameraDevice? input = _chooseInput();
      if (input == null) {
        _fail('No camera found.');
        return;
      }
      final List<CameraDevice> all = await _bridge.listDevices();
      final CameraDevice? loopback = all
          .cast<CameraDevice?>()
          .firstWhere((d) => d != null && d.isLoopback, orElse: () => null);
      if (loopback == null) {
        _fail('No v4l2loopback device found. See README for setup.');
        return;
      }

      debugPrint('horaloca: starting with input=${input.path} '
          '(color=${input.isColor}) output=${loopback.path}');

      // Seed with the freshest time so the first frame is correct.
      _config = _config.copyWith(text: _clock.currentFormatted());
      await _bridge.start(
        inputDevice: input.path,
        outputDevice: loopback.path,
        config: _config,
      );
      _activeInputPath = input.path;
      // Authoritative status arrives on the status stream (-> running).
    } catch (e) {
      _fail('Failed to start pipeline: $e');
    }
  }

  /// Stop the pipeline and release the cameras.
  Future<void> stopPipeline() async {
    try {
      await _bridge.stop();
    } catch (e) {
      _fail('Failed to stop pipeline: $e');
      return;
    }
    _activeInputPath = null;
    _setStatus(PipelineStatus.stopped);
  }

  /// Tray "Status" click handler.
  Future<void> toggleRunning() async {
    if (_state.isRunning) {
      await stopPipeline();
    } else {
      await startPipeline();
    }
  }

  /// Tray "Camera ▸ <device>" handler: remember the choice and (re)start the
  /// pipeline on that source so the switch takes effect immediately.
  Future<void> selectCamera(String path) async {
    _selectedPath = path;
    await _settings.setSelectedCameraPath(path);
    final bool wasRunning = _state.isRunning;
    if (wasRunning) {
      await stopPipeline();
    }
    await startPipeline();
    if (!wasRunning && !_state.isRunning) {
      // If it wasn't running and start failed, still refresh the menu.
      await _refreshTray();
    }
  }

  /// Tray "Refresh Timezone" handler.
  Future<void> refreshTimezone() async {
    final String tz = _clock.refreshTimezone();
    _state = _state.copyWith(timezoneName: tz);
    _config = _config.copyWith(text: _clock.currentFormatted());
    if (_state.isRunning) {
      unawaited(_bridge.updateOverlay(_config));
    }
    await _refreshTray();
    notifyListeners();
  }

  /// Phase 2 entry point: apply an edited overlay configuration (position,
  /// font, scale, PNG background…). Text is preserved from the live clock.
  Future<void> updateConfig(OverlayConfig newConfig) async {
    _config = newConfig.copyWith(text: _clock.currentFormatted());
    if (_state.isRunning) {
      unawaited(_bridge.updateOverlay(_config));
    }
    notifyListeners();
  }

  Future<void> quit() async {
    await dispose();
    TrayService.exitApp();
  }

  Future<void> _refreshTray() async {
    await _tray.updateMenu(_state,
        cameras: _cameras, selectedPath: _menuSelection());
  }

  void _setStatus(PipelineStatus status) {
    _state = _state.copyWith(status: status, clearError: true);
    unawaited(_refreshTray());
    notifyListeners();
  }

  void _fail(String message) {
    _state = _state.copyWith(status: PipelineStatus.error, errorMessage: message);
    debugPrint('horaloca: $message');
    unawaited(_refreshTray());
    notifyListeners();
  }

  @override
  Future<void> dispose() async {
    await _clockSub?.cancel();
    await _statusSub?.cancel();
    await _clock.dispose();
    await _tray.dispose();
    super.dispose();
  }
}
