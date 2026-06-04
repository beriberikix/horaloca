// Plain C++ mirror of the Dart `OverlayConfig`. Marshaled from the
// MethodChannel arguments map. Kept dependency-free (no GStreamer/Cairo) so it
// is trivial to copy under a lock.
#ifndef HORALOCA_VIDEO_OVERLAY_MODEL_H_
#define HORALOCA_VIDEO_OVERLAY_MODEL_H_

#include <string>

namespace horaloca {

// The 9-slot anchor grid, matching lib/models/overlay_position.dart. MVP only
// uses kBottomLeft, but the renderer handles every slot so Phase 2 is UI-only.
enum class OverlayPosition {
  kTopLeft,
  kTopCenter,
  kTopRight,
  kCenterLeft,
  kCenter,
  kCenterRight,
  kBottomLeft,
  kBottomCenter,
  kBottomRight,
};

// Parse the wire string (enum name from Dart) into an OverlayPosition,
// defaulting to bottom-left for unknown values (forward-compat).
OverlayPosition OverlayPositionFromWire(const std::string& value);

// Horizontal anchor fraction: 0.0 left, 0.5 center, 1.0 right.
double HorizontalAnchor(OverlayPosition p);
// Vertical anchor fraction: 0.0 top, 0.5 middle, 1.0 bottom.
double VerticalAnchor(OverlayPosition p);

// Everything the Cairo renderer needs to paint one badge.
struct OverlayModel {
  // The formatted string to draw, e.g. "03:45 AM (PST)".
  std::string text;

  OverlayPosition position = OverlayPosition::kBottomLeft;

  // Font family name resolved by Pango/Cairo (bundled "Ubuntu" by default).
  std::string font_family = "Ubuntu";

  // Multiplier on the resolution-derived base font size.
  double font_scale = 1.0;

  // Opacity 0..1 of the default dark block. Ignored when png_background_path
  // is non-empty.
  double background_opacity = 0.62;

  // Absolute path to a user PNG background, or empty for the default block.
  // (Phase 2 — the renderer already branches on it.)
  std::string png_background_path;
};

}  // namespace horaloca

#endif  // HORALOCA_VIDEO_OVERLAY_MODEL_H_
