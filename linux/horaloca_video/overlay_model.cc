#include "overlay_model.h"

namespace horaloca {

OverlayPosition OverlayPositionFromWire(const std::string& value) {
  if (value == "topLeft") return OverlayPosition::kTopLeft;
  if (value == "topCenter") return OverlayPosition::kTopCenter;
  if (value == "topRight") return OverlayPosition::kTopRight;
  if (value == "centerLeft") return OverlayPosition::kCenterLeft;
  if (value == "center") return OverlayPosition::kCenter;
  if (value == "centerRight") return OverlayPosition::kCenterRight;
  if (value == "bottomLeft") return OverlayPosition::kBottomLeft;
  if (value == "bottomCenter") return OverlayPosition::kBottomCenter;
  if (value == "bottomRight") return OverlayPosition::kBottomRight;
  return OverlayPosition::kBottomLeft;  // MVP default / forward-compat
}

double HorizontalAnchor(OverlayPosition p) {
  switch (p) {
    case OverlayPosition::kTopLeft:
    case OverlayPosition::kCenterLeft:
    case OverlayPosition::kBottomLeft:
      return 0.0;
    case OverlayPosition::kTopCenter:
    case OverlayPosition::kCenter:
    case OverlayPosition::kBottomCenter:
      return 0.5;
    case OverlayPosition::kTopRight:
    case OverlayPosition::kCenterRight:
    case OverlayPosition::kBottomRight:
      return 1.0;
  }
  return 0.0;
}

double VerticalAnchor(OverlayPosition p) {
  switch (p) {
    case OverlayPosition::kTopLeft:
    case OverlayPosition::kTopCenter:
    case OverlayPosition::kTopRight:
      return 0.0;
    case OverlayPosition::kCenterLeft:
    case OverlayPosition::kCenter:
    case OverlayPosition::kCenterRight:
      return 0.5;
    case OverlayPosition::kBottomLeft:
    case OverlayPosition::kBottomCenter:
    case OverlayPosition::kBottomRight:
      return 1.0;
  }
  return 1.0;
}

}  // namespace horaloca
