# Static library holding the app-local native video integration
# (GStreamer pipeline + Cairo overlay renderer + platform channels).
# Linked into the Flutter runner by linux/runner/CMakeLists.txt.

find_package(PkgConfig REQUIRED)
pkg_check_modules(GST REQUIRED IMPORTED_TARGET
  gstreamer-1.0
  gstreamer-video-1.0)
pkg_check_modules(CAIRO REQUIRED IMPORTED_TARGET cairo)
pkg_check_modules(PANGOCAIRO REQUIRED IMPORTED_TARGET pangocairo)

add_library(horaloca_video STATIC
  overlay_model.cc
  overlay_renderer.cc
  pipeline_controller.cc
  horaloca_video_plugin.cc
)

target_compile_features(horaloca_video PUBLIC cxx_std_17)

target_include_directories(horaloca_video PUBLIC
  "${CMAKE_CURRENT_SOURCE_DIR}")

target_link_libraries(horaloca_video PUBLIC
  flutter
  PkgConfig::GST
  PkgConfig::CAIRO
  PkgConfig::PANGOCAIRO)

# flutter_linux headers (FlMethodChannel etc.) come from the flutter target,
# which is defined by the runner before this subdirectory is added.
target_link_libraries(horaloca_video PRIVATE PkgConfig::GTK)
