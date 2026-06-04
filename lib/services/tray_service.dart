import 'dart:io';

import 'package:tray_manager/tray_manager.dart';

import '../app/app_state.dart';
import 'video_pipeline_bridge.dart';

/// Callbacks the tray invokes for each menu action. Wired up by [AppController].
class TrayCallbacks {
  const TrayCallbacks({
    required this.onToggleRunning,
    required this.onRefreshTimezone,
    required this.onSelectCamera,
    required this.onOpenSettings,
    required this.onQuit,
  });

  /// Start or stop the pipeline (driven from the dynamic Status item).
  final void Function() onToggleRunning;

  /// Re-read the host timezone.
  final void Function() onRefreshTimezone;

  /// Switch the source camera to the given /dev/videoN path.
  final void Function(String devicePath) onSelectCamera;

  /// Show the settings window.
  final void Function() onOpenSettings;

  /// Tear everything down and exit.
  final void Function() onQuit;
}

/// Owns the AppIndicator system-tray icon and its context menu.
///
/// Menu:
///   * Status: Running / Stopped   (click toggles the pipeline)
///   * Camera ▸  <list of cameras> (click switches source; current is checked)
///   * Refresh Timezone
///   * Timezone: <zone>            (disabled info line)
///   * ──────────
///   * Quit
///
/// On Linux both left- and right-click pop the context menu (AppIndicator has
/// no separate "primary activate" gesture), which matches the spec.
class TrayService with TrayListener {
  TrayService(this._callbacks);

  final TrayCallbacks _callbacks;

  // Distinct keys so onTrayMenuItemClick can dispatch without ambiguity.
  static const String _kStatus = 'status';
  static const String _kRefreshTz = 'refresh_tz';
  static const String _kSettings = 'settings';
  static const String _kQuit = 'quit';
  // Camera items use this prefix; the device path follows after it.
  static const String _kCameraPrefix = 'camera::';

  /// Initialise the tray icon and install the initial menu. [state] seeds the
  /// dynamic labels; [cameras]/[selectedPath] populate the Camera submenu.
  ///
  /// Note: we deliberately do NOT call `trayManager.setToolTip` — it is not
  /// implemented in the tray_manager Linux backend and throws
  /// MissingPluginException, which would otherwise abort app startup (and with
  /// it the video pipeline). The tooltip is non-essential.
  Future<void> init(
    AppState state, {
    List<CameraDevice> cameras = const <CameraDevice>[],
    String? selectedPath,
  }) async {
    trayManager.addListener(this);
    await trayManager.setIcon(_iconForStatus(state.status));
    await updateMenu(state, cameras: cameras, selectedPath: selectedPath);
  }

  /// Rebuild the menu to reflect the latest [state] + camera list.
  Future<void> updateMenu(
    AppState state, {
    List<CameraDevice> cameras = const <CameraDevice>[],
    String? selectedPath,
  }) async {
    await trayManager.setIcon(_iconForStatus(state.status));

    final String tzLabel = state.timezoneName.isEmpty
        ? 'Timezone: unknown'
        : 'Timezone: ${state.timezoneName}';

    final Menu menu = Menu(
      items: <MenuItem>[
        // Clicking the status line toggles the pipeline on/off.
        MenuItem(
          key: _kStatus,
          label: 'Status: ${state.status.label}',
        ),
        MenuItem.separator(),
        _buildCameraSubmenu(cameras, selectedPath),
        MenuItem.separator(),
        MenuItem(
          key: _kRefreshTz,
          label: 'Refresh Timezone',
        ),
        // A disabled informational line showing the resolved zone.
        MenuItem(
          key: 'tz_info',
          label: tzLabel,
          disabled: true,
        ),
        MenuItem.separator(),
        MenuItem(key: _kSettings, label: 'Settings…'),
        MenuItem(key: _kQuit, label: 'Quit'),
      ],
    );
    await trayManager.setContextMenu(menu);
  }

  /// Build the "Camera" submenu listing each detected source, with the active
  /// one checked. Mono/IR sensors are labelled so the user avoids them.
  MenuItem _buildCameraSubmenu(
      List<CameraDevice> cameras, String? selectedPath) {
    if (cameras.isEmpty) {
      return MenuItem(
        key: 'camera_none',
        label: 'Camera: none found',
        disabled: true,
      );
    }
    final List<MenuItem> items = <MenuItem>[
      for (final CameraDevice c in cameras)
        MenuItem.checkbox(
          key: '$_kCameraPrefix${c.path}',
          label: c.menuLabel,
          checked: c.path == selectedPath,
        ),
    ];
    return MenuItem.submenu(
      key: 'camera_menu',
      label: 'Camera',
      submenu: Menu(items: items),
    );
  }

  /// Choose the running vs stopped icon.
  String _iconForStatus(PipelineStatus status) {
    final bool active = status == PipelineStatus.running;
    return active
        ? 'assets/icons/tray_running.png'
        : 'assets/icons/tray_stopped.png';
  }

  // --- TrayListener -------------------------------------------------------

  @override
  void onTrayIconMouseDown() {
    // Left click → show the menu (AppIndicator convention on Linux).
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    final String key = menuItem.key ?? '';
    if (key.startsWith(_kCameraPrefix)) {
      _callbacks.onSelectCamera(key.substring(_kCameraPrefix.length));
      return;
    }
    switch (key) {
      case _kStatus:
        _callbacks.onToggleRunning();
        break;
      case _kRefreshTz:
        _callbacks.onRefreshTimezone();
        break;
      case _kSettings:
        _callbacks.onOpenSettings();
        break;
      case _kQuit:
        _callbacks.onQuit();
        break;
    }
  }

  Future<void> dispose() async {
    trayManager.removeListener(this);
    await trayManager.destroy();
  }

  /// Convenience used by the Quit path to actually terminate the process after
  /// teardown, since the window is normally hidden.
  static Never exitApp() {
    exit(0);
  }
}
