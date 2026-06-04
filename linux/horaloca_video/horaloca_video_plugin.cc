#include "horaloca_video_plugin.h"

#include <pango/pangocairo.h>

#include <algorithm>
#include <memory>
#include <string>
#include <vector>

#include "overlay_model.h"
#include "pipeline_controller.h"

namespace {

using horaloca::OverlayModel;
using horaloca::OverlayPositionFromWire;
using horaloca::PipelineController;
using horaloca::Status;
using horaloca::StatusToWire;
using horaloca::VideoDevice;

// Process-wide state for the channels. Created in
// horaloca_video_plugin_register and intentionally leaked for the process
// lifetime (the engine outlives any teardown we'd do here).
struct PluginState {
  std::unique_ptr<PipelineController> controller;
  FlEventChannel* status_channel = nullptr;  // owned by GObject ref
  bool listening = false;                    // is Dart subscribed?
};

// --- FlValue helpers -------------------------------------------------------

std::string GetString(FlValue* map, const char* key,
                      const std::string& fallback = "") {
  FlValue* v = fl_value_lookup_string(map, key);
  if (v != nullptr && fl_value_get_type(v) == FL_VALUE_TYPE_STRING) {
    return fl_value_get_string(v);
  }
  return fallback;
}

double GetDouble(FlValue* map, const char* key, double fallback) {
  FlValue* v = fl_value_lookup_string(map, key);
  if (v == nullptr) return fallback;
  switch (fl_value_get_type(v)) {
    case FL_VALUE_TYPE_FLOAT:
      return fl_value_get_float(v);
    case FL_VALUE_TYPE_INT:
      return static_cast<double>(fl_value_get_int(v));
    default:
      return fallback;
  }
}

// Colours travel as ARGB ints; the channel codec widens them to int64.
uint32_t GetColor(FlValue* map, const char* key, uint32_t fallback) {
  FlValue* v = fl_value_lookup_string(map, key);
  if (v != nullptr && fl_value_get_type(v) == FL_VALUE_TYPE_INT) {
    return static_cast<uint32_t>(fl_value_get_int(v) & 0xFFFFFFFF);
  }
  return fallback;
}

// Marshal a MethodChannel overlay map into the C++ OverlayModel.
OverlayModel ModelFromArgs(FlValue* map) {
  OverlayModel model;
  if (map == nullptr || fl_value_get_type(map) != FL_VALUE_TYPE_MAP) {
    return model;
  }
  model.text = GetString(map, "text");
  model.position = OverlayPositionFromWire(GetString(map, "position", "bottomLeft"));
  model.font_family = GetString(map, "fontFamily", "Ubuntu");
  model.font_scale = GetDouble(map, "fontScale", 1.0);
  model.corner_radius = GetDouble(map, "cornerRadius", 12.0);
  model.border_width = GetDouble(map, "borderWidth", 0.0);
  model.text_color = GetColor(map, "textColor", 0xFFFFFFFFu);
  model.background_color = GetColor(map, "backgroundColor", 0x9E000000u);
  model.border_color = GetColor(map, "borderColor", 0xFFFFFFFFu);
  return model;
}

// Enumerate the system's installed font families via Pango/fontconfig and
// return them (sorted, de-duplicated) as an FlValue string list for the
// settings UI font picker.
FlValue* ListFontFamilies() {
  FlValue* list = fl_value_new_list();
  PangoFontMap* font_map = pango_cairo_font_map_get_default();
  if (font_map == nullptr) return list;

  PangoFontFamily** families = nullptr;
  int n = 0;
  pango_font_map_list_families(font_map, &families, &n);

  std::vector<std::string> names;
  names.reserve(n);
  for (int i = 0; i < n; ++i) {
    const char* name = pango_font_family_get_name(families[i]);
    if (name != nullptr && name[0] != '\0') names.emplace_back(name);
  }
  g_free(families);

  std::sort(names.begin(), names.end());
  names.erase(std::unique(names.begin(), names.end()), names.end());
  for (const std::string& name : names) {
    fl_value_append_take(list, fl_value_new_string(name.c_str()));
  }
  return list;
}

// Push a status event up to Dart (if subscribed). Called from the controller's
// status callback, which runs on the GLib main context — safe for Flutter.
void SendStatus(PluginState* state, Status status, const std::string& error) {
  if (state->status_channel == nullptr || !state->listening) return;
  g_autoptr(FlValue) event = fl_value_new_map();
  fl_value_set_string_take(event, "status",
                           fl_value_new_string(StatusToWire(status)));
  if (error.empty()) {
    fl_value_set_string_take(event, "error", fl_value_new_null());
  } else {
    fl_value_set_string_take(event, "error",
                             fl_value_new_string(error.c_str()));
  }
  fl_event_channel_send(state->status_channel, event, nullptr, nullptr);
}

// --- MethodChannel handler -------------------------------------------------

void HandleMethodCall(FlMethodChannel* /*channel*/, FlMethodCall* method_call,
                      gpointer user_data) {
  auto* state = static_cast<PluginState*>(user_data);
  const gchar* method = fl_method_call_get_name(method_call);
  FlValue* args = fl_method_call_get_args(method_call);

  g_autoptr(FlMethodResponse) response = nullptr;

  if (g_strcmp0(method, "listDevices") == 0) {
    g_autoptr(FlValue) list = fl_value_new_list();
    for (const VideoDevice& d : state->controller->ListDevices()) {
      FlValue* item = fl_value_new_map();
      fl_value_set_string_take(item, "path", fl_value_new_string(d.path.c_str()));
      fl_value_set_string_take(item, "label",
                               fl_value_new_string(d.label.c_str()));
      fl_value_set_string_take(item, "isLoopback",
                               fl_value_new_bool(d.is_loopback));
      fl_value_set_string_take(item, "isColor", fl_value_new_bool(d.is_color));
      fl_value_set_string_take(item, "isMono", fl_value_new_bool(d.is_mono));
      fl_value_append_take(list, item);
    }
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(list));

  } else if (g_strcmp0(method, "start") == 0) {
    const std::string input = GetString(args, "inputDevice");
    const std::string output = GetString(args, "outputDevice");
    FlValue* overlay = fl_value_lookup_string(args, "overlay");
    state->controller->UpdateOverlay(ModelFromArgs(overlay));
    const bool ok = state->controller->Start(input, output);
    response = FL_METHOD_RESPONSE(
        fl_method_success_response_new(fl_value_new_bool(ok)));

  } else if (g_strcmp0(method, "stop") == 0) {
    state->controller->Stop();
    g_autoptr(FlValue) ok = fl_value_new_null();
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(ok));

  } else if (g_strcmp0(method, "updateOverlay") == 0) {
    state->controller->UpdateOverlay(ModelFromArgs(args));
    g_autoptr(FlValue) ok = fl_value_new_null();
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(ok));

  } else if (g_strcmp0(method, "listFonts") == 0) {
    g_autoptr(FlValue) list = ListFontFamilies();
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(list));

  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  fl_method_call_respond(method_call, response, nullptr);
}

// --- EventChannel stream handlers ------------------------------------------

FlMethodErrorResponse* OnListen(FlEventChannel* /*channel*/, FlValue* /*args*/,
                                gpointer user_data) {
  auto* state = static_cast<PluginState*>(user_data);
  state->listening = true;
  // Emit the current status immediately so the UI is correct on subscribe.
  SendStatus(state, state->controller->is_running() ? Status::kRunning
                                                    : Status::kStopped,
             "");
  return nullptr;
}

FlMethodErrorResponse* OnCancel(FlEventChannel* /*channel*/, FlValue* /*args*/,
                                gpointer user_data) {
  static_cast<PluginState*>(user_data)->listening = false;
  return nullptr;
}

}  // namespace

void horaloca_video_plugin_register(FlBinaryMessenger* messenger) {
  auto* state = new PluginState();  // leaked intentionally (process lifetime)
  state->controller = std::make_unique<PipelineController>();

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();

  FlMethodChannel* method_channel = fl_method_channel_new(
      messenger, "horaloca/video", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(method_channel, HandleMethodCall,
                                            state, nullptr);

  state->status_channel = fl_event_channel_new(
      messenger, "horaloca/video/status", FL_METHOD_CODEC(codec));
  fl_event_channel_set_stream_handlers(state->status_channel, OnListen,
                                       OnCancel, state, nullptr);

  // Bridge controller status -> EventChannel.
  state->controller->set_status_callback(
      [state](Status status, const std::string& error) {
        SendStatus(state, status, error);
      });
}
