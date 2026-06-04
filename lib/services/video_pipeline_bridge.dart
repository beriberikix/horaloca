import 'dart:async';

import 'package:flutter/services.dart';

import '../app/app_state.dart';
import '../models/overlay_config.dart';

/// A camera device discovered by the native plugin.
class CameraDevice {
  const CameraDevice({
    required this.path,
    required this.label,
    required this.isLoopback,
    required this.isColor,
    required this.isMono,
  });

  /// e.g. `/dev/video0`.
  final String path;

  /// Friendly card label, e.g. `Integrated Camera` or `horaloca Virtual Camera`.
  final String label;

  /// True when this device is the v4l2loopback sink we should output to.
  final bool isLoopback;

  /// True when the device advertises a colour pixel format (i.e. it is a normal
  /// RGB webcam). Drives the default source pick so we don't grab the
  /// greyscale IR camera.
  final bool isColor;

  /// True when the device enumerated formats but ALL were grey/IR (a mono
  /// face-unlock sensor). [isColor] and [isMono] both false => unknown.
  final bool isMono;

  /// A user-facing name for the tray menu, e.g. `Integrated Camera (/dev/video0)`.
  ///
  /// V4L2 card labels often carry a trailing ": <bus>" suffix; trim it so the
  /// menu is readable. The /dev path is always shown because a camera can
  /// expose several identically-named nodes — the path is how you tell them
  /// apart. Only tag mono/IR when we are *confident* (isMono), never on the
  /// inconclusive case.
  String get menuLabel {
    String name = label.trim();
    final int colon = name.indexOf(':');
    if (colon > 0) name = name.substring(0, colon).trim();
    if (name.isEmpty) name = path;
    final String base = name == path ? path : '$name ($path)';
    return isMono ? '$base — mono/IR' : base;
  }

  factory CameraDevice.fromMap(Map<Object?, Object?> map) {
    return CameraDevice(
      path: map['path'] as String? ?? '',
      label: map['label'] as String? ?? '',
      isLoopback: map['isLoopback'] as bool? ?? false,
      isColor: map['isColor'] as bool? ?? false,
      isMono: map['isMono'] as bool? ?? false,
    );
  }
}

/// Thin, typed Dart wrapper over the native `horaloca_video` plugin.
///
/// All video work happens natively (GStreamer + Cairo); this class only sends
/// commands and a small config map across the [MethodChannel], and exposes the
/// native lifecycle as a [Stream] over an [EventChannel]. Flutter never touches
/// raw frames.
class VideoPipelineBridge {
  VideoPipelineBridge({
    MethodChannel? methodChannel,
    EventChannel? statusChannel,
  })  : _method = methodChannel ?? const MethodChannel(_methodChannelName),
        _statusEvents = statusChannel ?? const EventChannel(_statusChannelName);

  static const String _methodChannelName = 'horaloca/video';
  static const String _statusChannelName = 'horaloca/video/status';

  final MethodChannel _method;
  final EventChannel _statusEvents;

  /// Lifecycle stream from the native side. Maps the raw event payload into a
  /// typed ([PipelineStatus], errorMessage) record.
  Stream<({PipelineStatus status, String? error})> get statusStream {
    return _statusEvents.receiveBroadcastStream().map((Object? event) {
      final Map<Object?, Object?> map =
          (event as Map?)?.cast<Object?, Object?>() ?? const <Object?, Object?>{};
      return (
        status: PipelineStatus.fromWire(map['status'] as String?),
        error: map['error'] as String?,
      );
    });
  }

  /// Enumerate physical inputs and the detected loopback sink.
  Future<List<CameraDevice>> listDevices() async {
    final List<Object?>? result =
        await _method.invokeMethod<List<Object?>>('listDevices');
    if (result == null) return const <CameraDevice>[];
    return result
        .whereType<Map<Object?, Object?>>()
        .map(CameraDevice.fromMap)
        .toList(growable: false);
  }

  /// Build and start the pipeline: [inputDevice] (physical) → overlay →
  /// [outputDevice] (loopback). Pass the initial overlay [config] so the very
  /// first frame already shows the time.
  ///
  /// When [outputDevice] is null the native side auto-selects the first device
  /// whose card label marks it as the horaloca loopback.
  Future<void> start({
    required String inputDevice,
    String? outputDevice,
    required OverlayConfig config,
  }) {
    return _method.invokeMethod<void>('start', <String, Object?>{
      'inputDevice': inputDevice,
      'outputDevice': outputDevice,
      'overlay': config.toMap(),
    });
  }

  /// Stop the pipeline and release both devices.
  Future<void> stop() => _method.invokeMethod<void>('stop');

  /// Push a new overlay config (typically just an updated [OverlayConfig.text]).
  /// Cheap: the native side swaps the model under a mutex; the pipeline keeps
  /// running and the change shows on the next rendered frame.
  Future<void> updateOverlay(OverlayConfig config) {
    return _method.invokeMethod<void>('updateOverlay', config.toMap());
  }
}
