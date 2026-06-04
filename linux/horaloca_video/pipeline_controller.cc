#include "pipeline_controller.h"

#include <fcntl.h>
#include <linux/videodev2.h>
#include <sys/ioctl.h>
#include <unistd.h>

#include <cstring>
#include <string>

namespace horaloca {

namespace {

// v4l2loopback identifies itself with this driver string in VIDIOC_QUERYCAP.
constexpr char kLoopbackDriver[] = "v4l2 loopback";

// Reference output geometry pushed to the virtual camera. Pinning these
// end-to-end is what keeps the loopback stream stable (no grey/flicker). Lower
// resolution physical cams are upscaled to this; this is also the natural hook
// for a future Phase-2 "output resolution" setting.
constexpr int kRefWidth = 1280;
constexpr int kRefHeight = 720;
constexpr int kRefFps = 30;

// Does this V4L2 fourcc denote a colour format (vs an IR/mono GREY format)?
// Whitelist the common colour formats UVC/webcams expose; anything else
// (GREY, Y8, Y10/12/16, …) is treated as mono/IR.
bool IsColorFourcc(__u32 f) {
  switch (f) {
    case V4L2_PIX_FMT_YUYV:
    case V4L2_PIX_FMT_UYVY:
    case V4L2_PIX_FMT_YVYU:
    case V4L2_PIX_FMT_NV12:
    case V4L2_PIX_FMT_NV21:
    case V4L2_PIX_FMT_YUV420:  // I420 / YU12
    case V4L2_PIX_FMT_YVU420:  // YV12
    case V4L2_PIX_FMT_MJPEG:
    case V4L2_PIX_FMT_JPEG:
    case V4L2_PIX_FMT_RGB24:
    case V4L2_PIX_FMT_BGR24:
    case V4L2_PIX_FMT_RGB565:
      return true;
    default:
      return false;
  }
}

// Enumerate the capture formats of an open fd for a given buffer type,
// accumulating counts and a fourcc string. Returns the number of formats found.
int EnumFormats(int fd, __u32 buf_type, bool* any_color, bool* any_other,
                std::string* fourccs) {
  int n = 0;
  v4l2_fmtdesc fmt{};
  fmt.type = buf_type;
  for (fmt.index = 0; ::ioctl(fd, VIDIOC_ENUM_FMT, &fmt) == 0; ++fmt.index) {
    ++n;
    const __u32 f = fmt.pixelformat;
    const char cc[5] = {static_cast<char>(f & 0xff),
                        static_cast<char>((f >> 8) & 0xff),
                        static_cast<char>((f >> 16) & 0xff),
                        static_cast<char>((f >> 24) & 0xff), 0};
    if (!fourccs->empty()) *fourccs += ',';
    *fourccs += cc;
    if (IsColorFourcc(f)) {
      *any_color = true;
    } else {
      *any_other = true;
    }
  }
  return n;
}

// Open a V4L2 node, read its capability struct, and classify it:
//   is_color  -> offers a colour format (normal RGB webcam)
//   is_mono   -> enumerated formats but ALL are grey/IR (face-unlock sensor)
//   neither   -> enumeration was inconclusive (treat as "unknown" upstream)
// Returns false if the node isn't a usable video device. Logs to stderr so
// device selection is debuggable from a terminal launch.
bool QueryCap(const std::string& path, v4l2_capability* cap, bool* is_color,
              bool* is_mono) {
  *is_color = false;
  *is_mono = false;
  int fd = ::open(path.c_str(), O_RDWR | O_NONBLOCK);
  if (fd < 0) {
    g_debug("horaloca: %s open failed (errno=%d)", path.c_str(), errno);
    return false;
  }
  if (::ioctl(fd, VIDIOC_QUERYCAP, cap) != 0) {
    ::close(fd);
    return false;
  }

  // Try single-plane first; some MIPI/IPU cams only enumerate via multiplanar.
  bool any_color = false, any_other = false;
  std::string fourccs;
  int n = EnumFormats(fd, V4L2_BUF_TYPE_VIDEO_CAPTURE, &any_color, &any_other,
                      &fourccs);
  if (n == 0) {
    n = EnumFormats(fd, V4L2_BUF_TYPE_VIDEO_CAPTURE_MPLANE, &any_color,
                    &any_other, &fourccs);
  }
  ::close(fd);

  *is_color = any_color;
  *is_mono = (n > 0 && !any_color);  // enumerated something, but no colour
  g_warning("horaloca: %s formats(%d)=[%s] -> color=%d mono=%d", path.c_str(),
            n, fourccs.c_str(), *is_color, *is_mono);
  return true;
}

}  // namespace

const char* StatusToWire(Status status) {
  switch (status) {
    case Status::kStopped:
      return "stopped";
    case Status::kStarting:
      return "starting";
    case Status::kRunning:
      return "running";
    case Status::kError:
      return "error";
  }
  return "stopped";
}

PipelineController::PipelineController() {
  // Idempotent; the runner may also init. Safe to call with null args.
  if (!gst_is_initialized()) {
    gst_init(nullptr, nullptr);
  }
}

PipelineController::~PipelineController() { Stop(); }

std::vector<VideoDevice> PipelineController::ListDevices() {
  std::vector<VideoDevice> devices;
  // Probe /dev/videoN directly rather than listing /dev. Inside snap
  // confinement the `camera` interface grants open() on /dev/video* but does
  // NOT grant readdir() on /dev, so std::filesystem::directory_iterator would
  // silently return nothing. Direct open()+QUERYCAP works with just `camera`.
  // 64 is the practical V4L2 ceiling and far above any real machine's count.
  constexpr int kMaxVideoNodes = 64;
  for (int i = 0; i < kMaxVideoNodes; ++i) {
    const std::string path = "/dev/video" + std::to_string(i);

    v4l2_capability cap{};
    bool is_color = false, is_mono = false;
    if (!QueryCap(path, &cap, &is_color, &is_mono)) continue;

    // Only surface nodes that can actually capture or output video. v4l2
    // exposes metadata-only nodes too (e.g. /dev/video1 on many UVC cams).
    const __u32 caps =
        (cap.capabilities & V4L2_CAP_DEVICE_CAPS) ? cap.device_caps
                                                  : cap.capabilities;
    const bool can_capture = caps & V4L2_CAP_VIDEO_CAPTURE;
    const bool can_output = caps & V4L2_CAP_VIDEO_OUTPUT;

    const std::string driver(reinterpret_cast<const char*>(cap.driver));
    const std::string card(reinterpret_cast<const char*>(cap.card));
    const bool is_loopback = driver == kLoopbackDriver;

    // Log every node we can open, including skipped ones, so device selection
    // is debuggable from a terminal launch (`horaloca`).
    g_message(
        "horaloca: %s driver='%s' card='%s' capture=%d output=%d color=%d "
        "loopback=%d%s",
        path.c_str(), driver.c_str(), card.c_str(), can_capture, can_output,
        is_color, is_loopback,
        (!can_capture && !can_output) ? " [skipped: no capture/output]" : "");

    if (!can_capture && !can_output) continue;

    devices.push_back(VideoDevice{path, card, is_loopback, is_color, is_mono});
  }
  return devices;
}

std::string PipelineController::AutoSelectLoopback() {
  for (const auto& d : ListDevices()) {
    if (d.is_loopback) return d.path;
  }
  return std::string();
}

bool PipelineController::Start(const std::string& input_device,
                               const std::string& output_device) {
  if (pipeline_ != nullptr) {
    // Already running; treat as success but re-report.
    ReportStatus(Status::kRunning, "");
    return true;
  }
  ReportStatus(Status::kStarting, "");

  const std::string output =
      output_device.empty() ? AutoSelectLoopback() : output_device;
  if (output.empty()) {
    ReportStatus(Status::kError,
                 "No v4l2loopback device found. See README for setup.");
    return false;
  }

  // Build the graph element-by-element so we can attach the draw callback and
  // give clear errors. The full chain:
  //
  //   v4l2src ! decodebin ! videoconvert ! videoscale ! videorate
  //           ! video/x-raw,BGRx,1280x720,30fps   (caps_in)
  //           ! cairooverlay                       (draws the badge)
  //           ! videoconvert
  //           ! video/x-raw,YUY2,1280x720,30fps    (caps_out)
  //           ! v4l2sink sync=false
  //
  // decodebin is the key to robustness + quality: many webcams only expose HD
  // over MJPEG (image/jpeg), with raw YUY2 limited to ~VGA. decodebin
  // auto-plugs jpegdec for MJPEG cams (true HD) and passes raw straight through
  // for others (e.g. mono/IR GRAY8) — so a single graph handles every device.
  // Pinning format+resolution+framerate from cairooverlay onward keeps the
  // loopback output stable (no grey/flicker for consumers like Chrome).
  // decodebin's src pad appears dynamically, so it is linked in OnDecodePadAdded.
  pipeline_ = gst_pipeline_new("horaloca-pipeline");
  GstElement* src = gst_element_factory_make("v4l2src", "src");
  GstElement* decode = gst_element_factory_make("decodebin", "decode");
  GstElement* conv_in = gst_element_factory_make("videoconvert", "conv_in");
  GstElement* scale = gst_element_factory_make("videoscale", "scale");
  GstElement* rate = gst_element_factory_make("videorate", "rate");
  GstElement* caps_in = gst_element_factory_make("capsfilter", "caps_in");
  cairo_overlay_ = gst_element_factory_make("cairooverlay", "overlay");
  GstElement* conv_out = gst_element_factory_make("videoconvert", "conv_out");
  GstElement* caps_out = gst_element_factory_make("capsfilter", "caps_out");
  GstElement* sink = gst_element_factory_make("v4l2sink", "sink");

  if (!pipeline_ || !src || !decode || !conv_in || !scale || !rate ||
      !caps_in || !cairo_overlay_ || !conv_out || !caps_out || !sink) {
    ReportStatus(Status::kError,
                 "Missing GStreamer element. Install gstreamer1.0-plugins-"
                 "good/base and the cairo plugin.");
    if (pipeline_) {
      gst_object_unref(pipeline_);
      pipeline_ = nullptr;
    }
    return false;
  }

  g_object_set(src, "device", input_device.c_str(), nullptr);
  // sync=false: the loopback sink is not a clock; don't block on timestamps.
  g_object_set(sink, "device", output.c_str(), "sync", FALSE, nullptr);

  // cairooverlay input: a Cairo-native RGB format, at the reference geometry.
  GstCaps* in_caps = gst_caps_new_simple(
      "video/x-raw", "format", G_TYPE_STRING, "BGRx", "width", G_TYPE_INT,
      kRefWidth, "height", G_TYPE_INT, kRefHeight, "framerate",
      GST_TYPE_FRACTION, kRefFps, 1, nullptr);
  g_object_set(caps_in, "caps", in_caps, nullptr);
  gst_caps_unref(in_caps);

  // Loopback output: YUY2 at the same fixed geometry/framerate.
  GstCaps* out_caps = gst_caps_new_simple(
      "video/x-raw", "format", G_TYPE_STRING, "YUY2", "width", G_TYPE_INT,
      kRefWidth, "height", G_TYPE_INT, kRefHeight, "framerate",
      GST_TYPE_FRACTION, kRefFps, 1, nullptr);
  g_object_set(caps_out, "caps", out_caps, nullptr);
  gst_caps_unref(out_caps);

  gst_bin_add_many(GST_BIN(pipeline_), src, decode, conv_in, scale, rate,
                   caps_in, cairo_overlay_, conv_out, caps_out, sink, nullptr);

  // src -> decodebin is static; decodebin -> conv_in is linked dynamically.
  if (!gst_element_link(src, decode)) {
    ReportStatus(Status::kError, "Failed to link camera source to decoder.");
    gst_object_unref(pipeline_);
    pipeline_ = nullptr;
    cairo_overlay_ = nullptr;
    return false;
  }
  g_signal_connect(decode, "pad-added", G_CALLBACK(OnDecodePadAdded), conv_in);

  if (!gst_element_link_many(conv_in, scale, rate, caps_in, cairo_overlay_,
                             conv_out, caps_out, sink, nullptr)) {
    ReportStatus(Status::kError, "Failed to link the GStreamer pipeline.");
    gst_object_unref(pipeline_);
    pipeline_ = nullptr;
    cairo_overlay_ = nullptr;
    return false;
  }

  // The renderer needs frame size (caps-changed) and paints each frame (draw).
  g_signal_connect(cairo_overlay_, "draw", G_CALLBACK(OnDraw), this);
  g_signal_connect(cairo_overlay_, "caps-changed", G_CALLBACK(OnCapsChanged),
                   this);

  // Watch the bus for async errors / EOS on the main context.
  GstBus* bus = gst_pipeline_get_bus(GST_PIPELINE(pipeline_));
  bus_watch_id_ = gst_bus_add_watch(bus, OnBusMessage, this);
  gst_object_unref(bus);

  const GstStateChangeReturn ret =
      gst_element_set_state(pipeline_, GST_STATE_PLAYING);
  if (ret == GST_STATE_CHANGE_FAILURE) {
    ReportStatus(Status::kError,
                 "Could not start the camera pipeline (device busy or "
                 "unsupported format?).");
    Stop();
    return false;
  }

  // PLAYING reached asynchronously; the bus ASYNC_DONE handler promotes us to
  // kRunning. Report optimistic running here so the UI is responsive.
  ReportStatus(Status::kRunning, "");
  return true;
}

void PipelineController::Stop() {
  if (pipeline_ == nullptr) return;
  if (bus_watch_id_ != 0) {
    g_source_remove(bus_watch_id_);
    bus_watch_id_ = 0;
  }
  gst_element_set_state(pipeline_, GST_STATE_NULL);
  gst_object_unref(pipeline_);
  pipeline_ = nullptr;
  cairo_overlay_ = nullptr;
  ReportStatus(Status::kStopped, "");
}

void PipelineController::ReportStatus(Status status, const std::string& error) {
  if (status_cb_) status_cb_(status, error);
}

// --- GStreamer callbacks ---------------------------------------------------

void PipelineController::OnDecodePadAdded(GstElement* /*decode*/, GstPad* pad,
                                          gpointer user_data) {
  GstElement* conv_in = GST_ELEMENT(user_data);
  GstPad* sink_pad = gst_element_get_static_pad(conv_in, "sink");
  if (sink_pad == nullptr) return;

  // Only link a video pad, and only once (decodebin emits per stream).
  if (!gst_pad_is_linked(sink_pad)) {
    GstCaps* caps = gst_pad_get_current_caps(pad);
    if (caps == nullptr) caps = gst_pad_query_caps(pad, nullptr);
    bool is_video = false;
    if (caps != nullptr) {
      GstStructure* s = gst_caps_get_structure(caps, 0);
      const gchar* name = gst_structure_get_name(s);
      is_video = name != nullptr && g_str_has_prefix(name, "video/");
      int cw = 0, ch = 0;
      gst_structure_get_int(s, "width", &cw);
      gst_structure_get_int(s, "height", &ch);
      // This is the real captured resolution (before we scale to the
      // reference geometry) — tells us if the cam gave HD or low-res raw.
      g_warning("horaloca: decoded capture caps %s %dx%d", name ? name : "?",
                cw, ch);
      gst_caps_unref(caps);
    }
    if (is_video) {
      const GstPadLinkReturn r = gst_pad_link(pad, sink_pad);
      if (GST_PAD_LINK_FAILED(r)) {
        g_warning("horaloca: failed to link decodebin -> videoconvert (%d)", r);
      }
    }
  }
  gst_object_unref(sink_pad);
}

void PipelineController::OnDraw(GstElement* /*overlay*/, cairo_t* cr,
                                guint64 /*timestamp*/, guint64 /*duration*/,
                                gpointer user_data) {
  static_cast<PipelineController*>(user_data)->renderer_.Draw(cr);
}

void PipelineController::OnCapsChanged(GstElement* /*overlay*/, GstCaps* caps,
                                       gpointer user_data) {
  GstStructure* s = gst_caps_get_structure(caps, 0);
  int width = 0, height = 0;
  gst_structure_get_int(s, "width", &width);
  gst_structure_get_int(s, "height", &height);
  g_warning("horaloca: overlay caps negotiated %dx%d", width, height);
  static_cast<PipelineController*>(user_data)->renderer_.SetFrameSize(width,
                                                                      height);
}

gboolean PipelineController::OnBusMessage(GstBus* /*bus*/, GstMessage* msg,
                                          gpointer user_data) {
  auto* self = static_cast<PipelineController*>(user_data);
  switch (GST_MESSAGE_TYPE(msg)) {
    case GST_MESSAGE_ERROR: {
      GError* err = nullptr;
      gchar* debug = nullptr;
      gst_message_parse_error(msg, &err, &debug);
      const std::string message = err ? err->message : "Unknown pipeline error";
      // Log the full detail to the terminal so failures are diagnosable.
      g_warning("horaloca: pipeline ERROR from %s: %s | debug: %s",
                GST_OBJECT_NAME(msg->src), message.c_str(),
                debug ? debug : "(none)");
      if (err) g_error_free(err);
      g_free(debug);
      self->ReportStatus(Status::kError, message);
      self->Stop();
      break;
    }
    case GST_MESSAGE_WARNING: {
      GError* err = nullptr;
      gchar* debug = nullptr;
      gst_message_parse_warning(msg, &err, &debug);
      g_warning("horaloca: pipeline WARNING from %s: %s | debug: %s",
                GST_OBJECT_NAME(msg->src), err ? err->message : "?",
                debug ? debug : "(none)");
      if (err) g_error_free(err);
      g_free(debug);
      break;
    }
    case GST_MESSAGE_EOS:
      self->ReportStatus(Status::kStopped, "");
      self->Stop();
      break;
    default:
      break;
  }
  return TRUE;  // keep watching
}

}  // namespace horaloca
