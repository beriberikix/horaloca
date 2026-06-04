import 'overlay_position.dart';

/// Immutable description of *what the overlay badge should look like* plus the
/// current [text] to draw.
///
/// This single struct is the contract between the Dart side and the native
/// Cairo renderer. It is intentionally complete on day one: the Phase 2
/// features (8-position grid, font/scale customisation, custom PNG background)
/// are already fields here, so adding them later is a settings-UI change only —
/// neither the wire format nor the renderer needs to grow.
///
/// The native side receives this as a plain `Map` over the MethodChannel (see
/// [toMap]) and mirrors it into the C++ `OverlayModel` struct.
class OverlayConfig {
  const OverlayConfig({
    this.text = '',
    this.position = OverlayPosition.bottomLeft,
    this.fontFamily = 'Ubuntu',
    this.fontScale = 1.0,
    this.use24HourClock = false,
    this.backgroundOpacity = 0.62,
    this.pngBackgroundPath,
  });

  /// The fully-formatted string to burn in, e.g. `03:45 AM (PST)`.
  /// Updated ~once per second by [ClockService] via the bridge.
  final String text;

  /// Which of the 9 anchor slots to use. MVP is always [OverlayPosition.bottomLeft].
  final OverlayPosition position;

  /// Font family name. Must match a family the native renderer can resolve
  /// (the bundled "Ubuntu" family by default). Phase 2 will let users pick
  /// any installed system font.
  final String fontFamily;

  /// Multiplier applied to the base font size (which is derived from frame
  /// height so the badge scales with resolution). Phase 2 exposes this.
  final double fontScale;

  /// 12h (`03:45 AM`) vs 24h (`15:45`) formatting. Owned here so the renderer
  /// and clock formatting share one source of truth.
  final bool use24HourClock;

  /// Opacity of the default dark background block, 0.0–1.0. Ignored when
  /// [pngBackgroundPath] is set.
  final double backgroundOpacity;

  /// Absolute path to a user-supplied PNG to use as the badge background
  /// instead of the default dark block. `null` in MVP. The renderer already
  /// branches on this; Phase 2 only adds a file picker that sets it.
  final String? pngBackgroundPath;

  /// Returns a copy with the given fields replaced. Used by [AppController]
  /// every time the clock ticks (only [text] changes) or a setting is edited.
  OverlayConfig copyWith({
    String? text,
    OverlayPosition? position,
    String? fontFamily,
    double? fontScale,
    bool? use24HourClock,
    double? backgroundOpacity,
    String? pngBackgroundPath,
    bool clearPngBackground = false,
  }) {
    return OverlayConfig(
      text: text ?? this.text,
      position: position ?? this.position,
      fontFamily: fontFamily ?? this.fontFamily,
      fontScale: fontScale ?? this.fontScale,
      use24HourClock: use24HourClock ?? this.use24HourClock,
      backgroundOpacity: backgroundOpacity ?? this.backgroundOpacity,
      pngBackgroundPath:
          clearPngBackground ? null : (pngBackgroundPath ?? this.pngBackgroundPath),
    );
  }

  /// Serialise for the platform channel. Keys are matched verbatim by the
  /// native `OverlayModel::fromMethodArgs`.
  Map<String, Object?> toMap() {
    return <String, Object?>{
      'text': text,
      'position': position.wireValue,
      'fontFamily': fontFamily,
      'fontScale': fontScale,
      'use24HourClock': use24HourClock,
      'backgroundOpacity': backgroundOpacity,
      'pngBackgroundPath': pngBackgroundPath,
    };
  }

  /// Reconstruct from a persisted/serialised map (e.g. future settings store).
  factory OverlayConfig.fromMap(Map<String, Object?> map) {
    return OverlayConfig(
      text: (map['text'] as String?) ?? '',
      position: OverlayPosition.fromWire(map['position'] as String?),
      fontFamily: (map['fontFamily'] as String?) ?? 'Ubuntu',
      fontScale: (map['fontScale'] as num?)?.toDouble() ?? 1.0,
      use24HourClock: (map['use24HourClock'] as bool?) ?? false,
      backgroundOpacity: (map['backgroundOpacity'] as num?)?.toDouble() ?? 0.62,
      pngBackgroundPath: map['pngBackgroundPath'] as String?,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is OverlayConfig &&
        other.text == text &&
        other.position == position &&
        other.fontFamily == fontFamily &&
        other.fontScale == fontScale &&
        other.use24HourClock == use24HourClock &&
        other.backgroundOpacity == backgroundOpacity &&
        other.pngBackgroundPath == pngBackgroundPath;
  }

  @override
  int get hashCode => Object.hash(
        text,
        position,
        fontFamily,
        fontScale,
        use24HourClock,
        backgroundOpacity,
        pngBackgroundPath,
      );
}
