// PipelineController owns the GStreamer graph:
//   v4l2src(physical) ! videoconvert ! cairooverlay ! videoconvert
//                     ! videoscale ! capsfilter ! v4l2sink(loopback)
// plus V4L2 device discovery and bus-error reporting.
#ifndef HORALOCA_VIDEO_PIPELINE_CONTROLLER_H_
#define HORALOCA_VIDEO_PIPELINE_CONTROLLER_H_

#include <gst/gst.h>

#include <functional>
#include <string>
#include <vector>

#include "overlay_renderer.h"

namespace horaloca {

// One discovered V4L2 device.
struct VideoDevice {
  std::string path;    // "/dev/video0"
  std::string label;   // card label from VIDIOC_QUERYCAP
  bool is_loopback;    // driver == "v4l2 loopback"
  bool is_color;       // advertises at least one color pixel format (not IR/mono)
};

// Pipeline lifecycle, mirrored to Dart's PipelineStatus.
enum class Status { kStopped, kStarting, kRunning, kError };

const char* StatusToWire(Status status);

// Callback delivering status changes to the EventChannel layer. Always invoked
// on the GLib main context thread (bus watch), so it is safe to touch Flutter.
using StatusCallback = std::function<void(Status, const std::string& error)>;

class PipelineController {
 public:
  PipelineController();
  ~PipelineController();

  void set_status_callback(StatusCallback cb) { status_cb_ = std::move(cb); }

  // Enumerate /dev/video* via VIDIOC_QUERYCAP. Loopback devices are flagged so
  // the Dart side can pick input vs output.
  std::vector<VideoDevice> ListDevices();

  // Build and start the pipeline. |output_device| may be empty to auto-pick the
  // first loopback. Returns false (and reports kError) on failure.
  bool Start(const std::string& input_device,
             const std::string& output_device);

  // Stop and tear down the graph; releases both devices.
  void Stop();

  // Forward an updated overlay model to the renderer (no pipeline restart).
  void UpdateOverlay(const OverlayModel& model) { renderer_.SetModel(model); }

  bool is_running() const { return pipeline_ != nullptr; }

 private:
  // GStreamer signal trampolines (static -> instance).
  // decodebin exposes its decoded src pad dynamically; link it to conv_in
  // (passed as user_data) when it appears.
  static void OnDecodePadAdded(GstElement* decode, GstPad* pad,
                               gpointer user_data);
  static void OnDraw(GstElement* overlay, cairo_t* cr, guint64 timestamp,
                     guint64 duration, gpointer user_data);
  static void OnCapsChanged(GstElement* overlay, GstCaps* caps,
                            gpointer user_data);
  static gboolean OnBusMessage(GstBus* bus, GstMessage* msg, gpointer user_data);

  void ReportStatus(Status status, const std::string& error);
  std::string AutoSelectLoopback();

  OverlayRenderer renderer_;
  StatusCallback status_cb_;

  GstElement* pipeline_ = nullptr;
  GstElement* cairo_overlay_ = nullptr;
  guint bus_watch_id_ = 0;
};

}  // namespace horaloca

#endif  // HORALOCA_VIDEO_PIPELINE_CONTROLLER_H_
