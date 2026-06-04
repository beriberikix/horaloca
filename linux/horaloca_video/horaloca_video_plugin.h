// Registers the horaloca_video platform channels against the Flutter engine.
// This is an app-local integration (not a published pub plugin), so it is
// compiled straight into the runner and registered from my_application.cc.
#ifndef HORALOCA_VIDEO_PLUGIN_H_
#define HORALOCA_VIDEO_PLUGIN_H_

#include <flutter_linux/flutter_linux.h>

G_BEGIN_DECLS

// Wire up the "horaloca/video" MethodChannel and "horaloca/video/status"
// EventChannel on |messenger|. Call once, after the FlView is created. The
// created objects live for the duration of the process.
void horaloca_video_plugin_register(FlBinaryMessenger* messenger);

G_END_DECLS

#endif  // HORALOCA_VIDEO_PLUGIN_H_
