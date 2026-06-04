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
constexpr double kSafeAreaFracX = 0.07;
constexpr double kSafeAreaFracY = 0.07;
// Inner padding between the text and the background block edge.
constexpr double kInnerPaddingX = 16.0;
constexpr double kInnerPaddingY = 9.0;
// Base font size is this fraction of frame height (before font_scale). At the
// pinned 720p reference this is ~37 px bold — readable in a Meet tile. This is
// the size of the time (first) line; the timezone line is drawn smaller.
constexpr double kFontHeightFraction = 0.052;
// The timezone line renders at this percent of the time line's size, so the
// always-longer location string doesn't dominate. (Pango markup relative size.)
constexpr int kTzLinePercent = 72;

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

// Set the cairo source from a 0xAARRGGBB colour.
void SetSourceArgb(cairo_t* cr, uint32_t argb) {
  const double a = ((argb >> 24) & 0xff) / 255.0;
  const double r = ((argb >> 16) & 0xff) / 255.0;
  const double g = ((argb >> 8) & 0xff) / 255.0;
  const double b = (argb & 0xff) / 255.0;
  cairo_set_source_rgba(cr, r, g, b, a);
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

void OverlayRenderer::Draw(cairo_t* cr) {
  // Take a snapshot of the model + size under the lock, then render lock-free.
  OverlayModel model;
  int width, height;
  {
    std::lock_guard<std::mutex> lock(mutex_);
    if (model_.text.empty()) return;  // nothing to draw yet
    model = model_;
    width = frame_width_;
    height = frame_height_;
  }

  // Robust frame size: "caps-changed" doesn't always fire with a dynamic-pad
  // (decodebin) graph, which would leave the size at 0. The clip region of a
  // fresh overlay context is the whole frame, so derive it from Cairo.
  if (width <= 0 || height <= 0) {
    double x1, y1, x2, y2;
    cairo_clip_extents(cr, &x1, &y1, &x2, &y2);
    width = static_cast<int>(x2 - x1);
    height = static_cast<int>(y2 - y1);
  }
  if (width <= 0 || height <= 0) return;

  const double scale = height / 720.0;  // everything scales off the reference

  // --- Lay out the (possibly multi-line) text, centered. ---
  const double font_px =
      std::round(height * kFontHeightFraction * std::max(0.2, model.font_scale));

  PangoLayout* layout = pango_cairo_create_layout(cr);
  PangoFontDescription* desc =
      pango_font_description_from_string(model.font_family.c_str());
  pango_font_description_set_absolute_size(desc, font_px * PANGO_SCALE);
  pango_font_description_set_weight(desc, PANGO_WEIGHT_BOLD);
  pango_layout_set_font_description(layout, desc);
  pango_layout_set_alignment(layout, PANGO_ALIGN_CENTER);

  // Render the time (first line) at the base size and the timezone line(s)
  // smaller, via Pango markup. Text is escaped so city/country names can't
  // break the markup.
  {
    const size_t nl = model.text.find('\n');
    const std::string time_line =
        nl == std::string::npos ? model.text : model.text.substr(0, nl);
    gchar* time_esc = g_markup_escape_text(time_line.c_str(), -1);
    std::string markup = time_esc;
    g_free(time_esc);
    if (nl != std::string::npos) {
      gchar* tz_esc = g_markup_escape_text(model.text.c_str() + nl + 1, -1);
      markup += "\n<span size=\"" + std::to_string(kTzLinePercent) + "%\">";
      markup += tz_esc;
      markup += "</span>";
      g_free(tz_esc);
    }
    pango_layout_set_markup(layout, markup.c_str(), -1);
  }

  // Title-safe insets and the badge's internal padding.
  const double pad_in_x = kInnerPaddingX * scale;
  const double pad_in_y = kInnerPaddingY * scale;
  const double pad_x = width * kSafeAreaFracX;
  const double pad_y = height * kSafeAreaFracY;

  int text_w_pango = 0, text_h_pango = 0;
  pango_layout_get_pixel_size(layout, &text_w_pango, &text_h_pango);
  // Never let the badge overflow the frame: if the text is wider than the room
  // inside the safe area, constrain the layout width (the long line wraps);
  // otherwise pin width to the widest line so CENTER centers shorter lines.
  const double max_text_w = width - 2 * pad_x - 2 * pad_in_x;
  if (max_text_w > 0 && text_w_pango > max_text_w) {
    pango_layout_set_width(layout, static_cast<int>(max_text_w * PANGO_SCALE));
    pango_layout_get_pixel_size(layout, &text_w_pango, &text_h_pango);
  } else {
    pango_layout_set_width(layout, text_w_pango * PANGO_SCALE);
  }
  const double text_w = text_w_pango;
  const double text_h = text_h_pango;

  // --- Badge box size + anchored, title-safe position. ---
  const double box_w = text_w + 2 * pad_in_x;
  const double box_h = text_h + 2 * pad_in_y;

  const double hx = HorizontalAnchor(model.position);
  const double vy = VerticalAnchor(model.position);

  double box_x = pad_x + hx * (width - 2 * pad_x - box_w);
  double box_y = pad_y + vy * (height - 2 * pad_y - box_h);
  box_x = std::clamp(box_x, pad_x, std::max(pad_x, width - pad_x - box_w));
  box_y = std::clamp(box_y, pad_y, std::max(pad_y, height - pad_y - box_h));

  // --- Background block (rounded or square), then optional border. ---
  const double radius = std::max(0.0, model.corner_radius * scale);
  if (radius > 0.5) {
    RoundedRect(cr, box_x, box_y, box_w, box_h, std::min(radius, box_h / 2.0));
  } else {
    cairo_rectangle(cr, box_x, box_y, box_w, box_h);
  }
  SetSourceArgb(cr, model.background_color);
  cairo_fill_preserve(cr);  // keep the path so we can stroke the border on it

  if (model.border_width > 0.0) {
    cairo_set_line_width(cr, std::max(1.0, model.border_width * scale));
    SetSourceArgb(cr, model.border_color);
    cairo_stroke(cr);
  } else {
    cairo_new_path(cr);  // discard the preserved path
  }

  // --- Text. ---
  cairo_move_to(cr, box_x + pad_in_x, box_y + pad_in_y);
  SetSourceArgb(cr, model.text_color);
  pango_cairo_show_layout(cr, layout);

  pango_font_description_free(desc);
  g_object_unref(layout);
}

}  // namespace horaloca
