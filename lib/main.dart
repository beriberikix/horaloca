import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:window_manager/window_manager.dart';

import 'app/app_controller.dart';
import 'services/clock_service.dart';
import 'services/settings_store.dart';
import 'services/tray_service.dart';
import 'services/tz_locations.dart';
import 'services/video_pipeline_bridge.dart';
import 'ui/settings_window.dart';

/// horaloca entry point.
///
/// The app is a *background* utility: at launch we hide the main window and
/// live in the system tray. The (currently minimal) window is only the Phase 2
/// settings surface; it can be re-shown later from a tray menu item.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Configure the window as a fixed-size settings panel (it is not the primary
  // surface — the app lives in the tray). A fixed size avoids the cramped
  // default and keeps the controls laid out predictably.
  await windowManager.ensureInitialized();
  const Size kSettingsSize = Size(460, 780);
  const WindowOptions windowOptions = WindowOptions(
    size: kSettingsSize,
    minimumSize: kSettingsSize,
    maximumSize: kSettingsSize,
    center: true,
    skipTaskbar: true,
    titleBarStyle: TitleBarStyle.normal,
    title: 'horaloca',
  );
  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.setResizable(false); // fixed-size panel
    // Stay out of sight; the tray is the real UI.
    await windowManager.hide();
    await windowManager.setPreventClose(true); // closing hides instead of quits
  });

  // Compose the object graph. Each dependency is constructed here so it can be
  // swapped in tests.
  final TzLocations tzLocations = await _loadTzLocations();
  final ClockService clock = ClockService(locations: tzLocations);
  final VideoPipelineBridge bridge = VideoPipelineBridge();
  final SettingsStore settings = SettingsStore();
  final AppController controller = AppController(
    clock: clock,
    bridge: bridge,
    settings: settings,
    trayFactory: TrayService.new,
  );

  // Start stopped — the camera only turns on when the user chooses (tray
  // "Status" or the Settings window's Start button). This keeps the webcam
  // light off until explicitly requested.
  await controller.initialize(autoStart: false);

  runApp(HoralocaApp(controller: controller));
}

/// Load the bundled IANA tz data files and build the zone -> "City, Country"
/// resolver. Failures degrade gracefully to an empty resolver (city-only).
Future<TzLocations> _loadTzLocations() async {
  try {
    final String zone = await rootBundle.loadString('assets/tzdata/zone1970.tab');
    final String iso = await rootBundle.loadString('assets/tzdata/iso3166.tab');
    return TzLocations.parse(zone1970Tab: zone, iso3166Tab: iso);
  } catch (_) {
    return TzLocations.empty();
  }
}

/// The Flutter UI shell. For MVP this is just the (hidden) settings window;
/// it exists so the engine/runtime stays alive to host the platform channels
/// and the tray.
class HoralocaApp extends StatelessWidget {
  const HoralocaApp({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'horaloca',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFFE95420), // Ubuntu orange
        useMaterial3: true,
        fontFamily: 'Ubuntu',
      ),
      home: SettingsWindow(controller: controller),
    );
  }
}
