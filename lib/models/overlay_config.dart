import 'overlay_position.dart';

/// Immutable description of *what the overlay badge looks like* plus the current
/// [text] to draw.
///
/// This single struct is the contract between Dart and the native Cairo
/// renderer. Phase 2 replaced the original opacity/PNG fields with explicit
/// styling (corner, border, and independent text/background/border colours) and
/// a multi-line [text] (time on top, timezone line below).
///
/// Colours are plain 32-bit ARGB ints (`0xAARRGGBB`) on the wire — the same
/// representation Flutter's `Color` uses — so they marshal trivially to the
/// native side.
class OverlayConfig {
  const OverlayConfig({
    this.text = '',
    this.position = OverlayPosition.bottomLeft,
    this.fontFamily = 'Ubuntu',
    this.fontScale = 1.0,
    this.use24HourClock = false,
    this.cornerRadius = 12.0,
    this.borderWidth = 0.0,
    this.textColor = 0xFFFFFFFF,
    this.backgroundColor = 0x9E000000,
    this.borderColor = 0xFFFFFFFF,
  });

  /// The string to burn in. Multi-line: `"11:35 AM\nCST (Taipei, Taiwan)"`.
  /// Updated by [ClockService] via the bridge; the renderer stacks the lines
  /// centered.
  final String text;

  /// Which of the 9 anchor slots to use.
  final OverlayPosition position;

  /// Font family name resolved by Pango/fontconfig (one of the machine's real
  /// installed families).
  final String fontFamily;

  /// Multiplier on the resolution-derived base font size.
  final double fontScale;

  /// 12h (`03:45 AM`) vs 24h (`15:45`) time formatting.
  final bool use24HourClock;

  /// Background block corner radius in px. `0` = square corners.
  final double cornerRadius;

  /// Border stroke width in px. `0` = no border. (UI offers 0 or 1.)
  final double borderWidth;

  /// Text colour, ARGB `0xAARRGGBB`.
  final int textColor;

  /// Background block colour, ARGB (alpha lets the block be semi-transparent).
  final int backgroundColor;

  /// Border colour, ARGB. Ignored when [borderWidth] is 0.
  final int borderColor;

  /// Returns a copy with the given fields replaced. The clock uses this every
  /// tick (only [text] changes); the settings UI uses it per edited control.
  OverlayConfig copyWith({
    String? text,
    OverlayPosition? position,
    String? fontFamily,
    double? fontScale,
    bool? use24HourClock,
    double? cornerRadius,
    double? borderWidth,
    int? textColor,
    int? backgroundColor,
    int? borderColor,
  }) {
    return OverlayConfig(
      text: text ?? this.text,
      position: position ?? this.position,
      fontFamily: fontFamily ?? this.fontFamily,
      fontScale: fontScale ?? this.fontScale,
      use24HourClock: use24HourClock ?? this.use24HourClock,
      cornerRadius: cornerRadius ?? this.cornerRadius,
      borderWidth: borderWidth ?? this.borderWidth,
      textColor: textColor ?? this.textColor,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      borderColor: borderColor ?? this.borderColor,
    );
  }

  /// Serialise for the platform channel / persistence. Keys are matched
  /// verbatim by the native `OverlayModel::fromMethodArgs`.
  Map<String, Object?> toMap() {
    return <String, Object?>{
      'text': text,
      'position': position.wireValue,
      'fontFamily': fontFamily,
      'fontScale': fontScale,
      'use24HourClock': use24HourClock,
      'cornerRadius': cornerRadius,
      'borderWidth': borderWidth,
      'textColor': textColor,
      'backgroundColor': backgroundColor,
      'borderColor': borderColor,
    };
  }

  /// Reconstruct from a persisted/serialised map. Unknown/missing keys fall
  /// back to the constructor defaults.
  factory OverlayConfig.fromMap(Map<String, Object?> map) {
    const OverlayConfig d = OverlayConfig();
    return OverlayConfig(
      text: (map['text'] as String?) ?? '',
      position: OverlayPosition.fromWire(map['position'] as String?),
      fontFamily: (map['fontFamily'] as String?) ?? d.fontFamily,
      fontScale: (map['fontScale'] as num?)?.toDouble() ?? d.fontScale,
      use24HourClock: (map['use24HourClock'] as bool?) ?? d.use24HourClock,
      cornerRadius: (map['cornerRadius'] as num?)?.toDouble() ?? d.cornerRadius,
      borderWidth: (map['borderWidth'] as num?)?.toDouble() ?? d.borderWidth,
      textColor: (map['textColor'] as num?)?.toInt() ?? d.textColor,
      backgroundColor:
          (map['backgroundColor'] as num?)?.toInt() ?? d.backgroundColor,
      borderColor: (map['borderColor'] as num?)?.toInt() ?? d.borderColor,
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
        other.cornerRadius == cornerRadius &&
        other.borderWidth == borderWidth &&
        other.textColor == textColor &&
        other.backgroundColor == backgroundColor &&
        other.borderColor == borderColor;
  }

  @override
  int get hashCode => Object.hash(
        text,
        position,
        fontFamily,
        fontScale,
        use24HourClock,
        cornerRadius,
        borderWidth,
        textColor,
        backgroundColor,
        borderColor,
      );
}
