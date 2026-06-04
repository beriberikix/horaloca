// OverlayRenderer draws the time badge onto each video frame via GStreamer's
// `cairooverlay` element. This is the single rendering path: the MVP dark-block
// badge AND every Phase 2 styling option (8 positions, font/scale, custom PNG
// background) are parameters of the same draw routine.
#ifndef HORALOCA_VIDEO_OVERLAY_RENDERER_H_
#define HORALOCA_VIDEO_OVERLAY_RENDERER_H_

#include <cairo/cairo.h>

#include <mutex>
#include <string>

#include "overlay_model.h"

namespace horaloca {

class OverlayRenderer {
 public:
  OverlayRenderer() = default;

  // Thread-safe model swap. Called from the Flutter platform thread whenever
  // the clock ticks or a setting changes; read from the streaming thread in
  // Draw(). Cheap copy under a mutex.
  void SetModel(const OverlayModel& model);

  // Record the negotiated frame size, from cairooverlay's "caps-changed".
  void SetFrameSize(int width, int height);

  // The cairooverlay "draw" callback body. Renders the current model onto |cr|.
  // Runs on a GStreamer streaming thread.
  void Draw(cairo_t* cr);

 private:
  // Resolve the PNG background once and cache it; reloaded if the path changes.
  cairo_surface_t* LoadPngBackground(const std::string& path);

  std::mutex mutex_;
  OverlayModel model_;
  int frame_width_ = 0;
  int frame_height_ = 0;

  // Cache for the Phase 2 custom PNG background.
  std::string cached_png_path_;
  cairo_surface_t* cached_png_ = nullptr;
};

}  // namespace horaloca

#endif  // HORALOCA_VIDEO_OVERLAY_RENDERER_H_
