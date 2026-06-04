// Plain C++ mirror of the Dart `OverlayConfig`. Marshaled from the
// MethodChannel arguments map. Kept dependency-free (no GStreamer/Cairo) so it
// is trivial to copy under a lock.
#ifndef HORALOCA_VIDEO_OVERLAY_MODEL_H_
#define HORALOCA_VIDEO_OVERLAY_MODEL_H_

#include <cstdint>
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

// Everything the Cairo renderer needs to paint one badge. Mirrors the Dart
// OverlayConfig. Multi-line text is stacked (centered) by the renderer.
struct OverlayModel {
  // The formatted string to draw, e.g. "11:35 AM\nCST (Taipei, Taiwan)".
  std::string text;

  OverlayPosition position = OverlayPosition::kBottomLeft;

  // Font family name resolved by Pango/fontconfig.
  std::string font_family = "Ubuntu";

  // Multiplier on the resolution-derived base font size.
  double font_scale = 1.0;

  // Background block corner radius in px (0 = square).
  double corner_radius = 12.0;

  // Border stroke width in px (0 = no border).
  double border_width = 0.0;

  // ARGB colours (0xAARRGGBB).
  uint32_t text_color = 0xFFFFFFFFu;
  uint32_t background_color = 0x9E000000u;
  uint32_t border_color = 0xFFFFFFFFu;
};

}  // namespace horaloca

#endif  // HORALOCA_VIDEO_OVERLAY_MODEL_H_
