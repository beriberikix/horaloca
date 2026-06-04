#include "overlay_renderer.h"

#include <pango/pangocairo.h>

#include <algorithm>
#include <cmath>

namespace horaloca {

namespace {

// "Title-safe" inset from each frame edge, as a fraction of the frame's width
// (horizontal) and height (vertical). Video-call apps (Meet, Zoom) center-crop
// the feed to fill a differently-shaped tile, so a badge hugging the edge gets
// sliced off. 5.5% per side keeps it inside the region that survives a typical
// crop — the broadcast title-safe convention — while still reading as "corner".
constexpr double kSafeAreaFracX = 0.055;
constexpr double kSafeAreaFracY = 0.055;
// Inner padding between the text and the background block edge.
constexpr double kInnerPaddingX = 16.0;
constexpr double kInnerPaddingY = 9.0;
// Corner radius of the default dark block.
constexpr double kCornerRadius = 9.0;
// Base font size is this fraction of frame height (before font_scale). At the
// pinned 720p reference this is ~37 px bold — comfortably readable in a Meet
// tile, even when that tile is scaled down in a grid.
constexpr double kFontHeightFraction = 0.052;

// Append a rounded-rectangle subpath to |cr|.
void RoundedRect(cairo_t* cr, double x, double y, double w, double h, double r) {
  const double kDegrees = M_PI / 180.0;
  cairo_new_sub_path(cr);
  cairo_arc(cr, x + w - r, y + r, r, -90 * kDegrees, 0 * kDegrees);
  cairo_arc(cr, x + w - r, y + h - r, r, 0 * kDegrees, 90 * kDegrees);
  cairo_arc(cr, x + r, y + h - r, r, 90 * kDegrees, 180 * kDegrees);
  cairo_arc(cr, x + r, y + r, r, 180 * kDegrees, 270 * kDegrees);
  cairo_close_path(cr);
}

}  // namespace

void OverlayRenderer::SetModel(const OverlayModel& model) {
  std::lock_guard<std::mutex> lock(mutex_);
  model_ = model;
}

void OverlayRenderer::SetFrameSize(int width, int height) {
  std::lock_guard<std::mutex> lock(mutex_);
  frame_width_ = width;
  frame_height_ = height;
}

cairo_surface_t* OverlayRenderer::LoadPngBackground(const std::string& path) {
  if (path == cached_png_path_ && cached_png_ != nullptr) {
    return cached_png_;
  }
  if (cached_png_ != nullptr) {
    cairo_surface_destroy(cached_png_);
    cached_png_ = nullptr;
  }
  cached_png_path_ = path;
  if (path.empty()) return nullptr;
  cairo_surface_t* surface = cairo_image_surface_create_from_png(path.c_str());
  if (cairo_surface_status(surface) != CAIRO_STATUS_SUCCESS) {
    cairo_surface_destroy(surface);
    cached_png_ = nullptr;
    return nullptr;
  }
  cached_png_ = surface;
  return cached_png_;
}

void OverlayRenderer::Draw(cairo_t* cr) {
  // Take a snapshot of the model + size under the lock, then render lock-free.
  OverlayModel model;
  int width, height;
  cairo_surface_t* png;
  {
    std::lock_guard<std::mutex> lock(mutex_);
    if (model_.text.empty()) return;  // nothing to draw yet
    model = model_;
    width = frame_width_;
    height = frame_height_;
    png = LoadPngBackground(model_.png_background_path);
  }

  // Robust frame size: the "caps-changed" signal does not always fire (it can
  // be missed with a decodebin/dynamic-pad graph), which previously left the
  // size at 0 and the badge undrawn. Derive it straight from the Cairo context
  // when we don't have it — the clip region of a fresh overlay context is the
  // whole frame.
  if (width <= 0 || height <= 0) {
    double x1, y1, x2, y2;
    cairo_clip_extents(cr, &x1, &y1, &x2, &y2);
    width = static_cast<int>(x2 - x1);
    height = static_cast<int>(y2 - y1);
  }
  if (width <= 0 || height <= 0) return;

  // --- Lay out the text with Pango so we get accurate metrics. ---
  const double font_px =
      std::round(height * kFontHeightFraction * std::max(0.2, model.font_scale));

  PangoLayout* layout = pango_cairo_create_layout(cr);
  PangoFontDescription* desc =
      pango_font_description_from_string(model.font_family.c_str());
  // Pango expects size in points * PANGO_SCALE; we drive directly in px via
  // absolute size so the badge scales with resolution.
  pango_font_description_set_absolute_size(desc, font_px * PANGO_SCALE);
  pango_font_description_set_weight(desc, PANGO_WEIGHT_BOLD);
  pango_layout_set_font_description(layout, desc);
  pango_layout_set_text(layout, model.text.c_str(), -1);

  int text_w_pango = 0, text_h_pango = 0;
  pango_layout_get_pixel_size(layout, &text_w_pango, &text_h_pango);
  const double text_w = text_w_pango;
  const double text_h = text_h_pango;

  // --- Compute the badge box (background block) size & anchored position. ---
  const double box_w = text_w + 2 * kInnerPaddingX;
  const double box_h = text_h + 2 * kInnerPaddingY;

  // Per-axis title-safe insets so the badge survives the consumer's crop.
  const double pad_x = width * kSafeAreaFracX;
  const double pad_y = height * kSafeAreaFracY;
  const double hx = HorizontalAnchor(model.position);
  const double vy = VerticalAnchor(model.position);

  // Place the box so its anchored corner/edge respects the safe inset.
  double box_x = pad_x + hx * (width - 2 * pad_x - box_w);
  double box_y = pad_y + vy * (height - 2 * pad_y - box_h);
  box_x = std::clamp(box_x, pad_x, std::max(pad_x, width - pad_x - box_w));
  box_y = std::clamp(box_y, pad_y, std::max(pad_y, height - pad_y - box_h));

  // --- Draw the background: either the user PNG or the default dark block. ---
  if (png != nullptr) {
    // Phase 2: stretch the PNG to the badge box. Anchored identically.
    const double png_w = cairo_image_surface_get_width(png);
    const double png_h = cairo_image_surface_get_height(png);
    cairo_save(cr);
    cairo_translate(cr, box_x, box_y);
    if (png_w > 0 && png_h > 0) {
      cairo_scale(cr, box_w / png_w, box_h / png_h);
    }
    cairo_set_source_surface(cr, png, 0, 0);
    cairo_paint(cr);
    cairo_restore(cr);
  } else {
    cairo_set_source_rgba(cr, 0.0, 0.0, 0.0,
                          std::clamp(model.background_opacity, 0.0, 1.0));
    RoundedRect(cr, box_x, box_y, box_w, box_h, kCornerRadius);
    cairo_fill(cr);
  }

  // --- Draw the text (white, centered in the box) with a subtle shadow for
  // readability over bright PNG backgrounds. ---
  const double text_x = box_x + kInnerPaddingX;
  const double text_y = box_y + kInnerPaddingY;

  cairo_move_to(cr, text_x + 1, text_y + 1);
  cairo_set_source_rgba(cr, 0.0, 0.0, 0.0, 0.55);  // shadow
  pango_cairo_show_layout(cr, layout);

  cairo_move_to(cr, text_x, text_y);
  cairo_set_source_rgb(cr, 1.0, 1.0, 1.0);  // white text
  pango_cairo_show_layout(cr, layout);

  pango_font_description_free(desc);
  g_object_unref(layout);
}

}  // namespace horaloca
