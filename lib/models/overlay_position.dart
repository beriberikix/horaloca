/// Where the time badge is anchored within the video frame.
///
/// Phase 1 (MVP) only ever uses [bottomLeft], but the full 9-slot grid is
/// defined here from day one so that the Phase 2 "8-position perimeter grid"
/// settings UI is a pure presentation change — the model, the platform-channel
/// wire format, and the native Cairo renderer already understand every slot.
///
/// The grid (the `center` slot is included for completeness even though the
/// product spec only exposes the 8 perimeter positions):
///
/// ```
///   topLeft      topCenter      topRight
///   centerLeft   center         centerRight
///   bottomLeft   bottomCenter   bottomRight
/// ```
enum OverlayPosition {
  topLeft,
  topCenter,
  topRight,
  centerLeft,
  center,
  centerRight,
  bottomLeft,
  bottomCenter,
  bottomRight;

  /// The horizontal anchor as a fraction (0.0 = left edge, 1.0 = right edge).
  ///
  /// The renderer combines this with a fixed pixel padding so the badge never
  /// touches the frame border. Kept here (rather than in the renderer) so the
  /// Dart settings UI can preview placement without a round-trip to native.
  double get horizontalAnchor {
    switch (this) {
      case OverlayPosition.topLeft:
      case OverlayPosition.centerLeft:
      case OverlayPosition.bottomLeft:
        return 0.0;
      case OverlayPosition.topCenter:
      case OverlayPosition.center:
      case OverlayPosition.bottomCenter:
        return 0.5;
      case OverlayPosition.topRight:
      case OverlayPosition.centerRight:
      case OverlayPosition.bottomRight:
        return 1.0;
    }
  }

  /// The vertical anchor as a fraction (0.0 = top edge, 1.0 = bottom edge).
  double get verticalAnchor {
    switch (this) {
      case OverlayPosition.topLeft:
      case OverlayPosition.topCenter:
      case OverlayPosition.topRight:
        return 0.0;
      case OverlayPosition.centerLeft:
      case OverlayPosition.center:
      case OverlayPosition.centerRight:
        return 0.5;
      case OverlayPosition.bottomLeft:
      case OverlayPosition.bottomCenter:
      case OverlayPosition.bottomRight:
        return 1.0;
    }
  }

  /// Stable string used on the platform channel and in persisted settings.
  /// Using the enum name keeps the wire format human-readable and
  /// forward-compatible.
  String get wireValue => name;

  /// Parse a [wireValue] back into an [OverlayPosition], falling back to the
  /// MVP default when an unknown value is encountered (forward-compat safety).
  static OverlayPosition fromWire(String? value) {
    return OverlayPosition.values.firstWhere(
      (p) => p.name == value,
      orElse: () => OverlayPosition.bottomLeft,
    );
  }
}
