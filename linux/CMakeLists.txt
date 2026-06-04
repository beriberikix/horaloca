# Project-level CMake config for the horaloca Linux desktop app.
# Structure mirrors the standard `flutter create` Linux template; the only
# customisation is the horaloca_video subproject linked into the runner.
cmake_minimum_required(VERSION 3.13)
project(runner LANGUAGES CXX)

# --- Flutter-snap clang / host-libstdc++ workaround -------------------------
# The Flutter snap builds with its bundled clang, which by default picks up the
# host's NEWEST libstdc++ headers. On hosts with GCC 15+, libstdc++'s <new>
# applies __alloc_align__ to the std::align_val_t operator-new overloads, which
# this clang rejects ("attribute argument may only refer to a function
# parameter of integer type"), breaking every C++ translation unit.
#
# Redirect clang to the snap's OWN bundled GCC toolchain (its gcc-10 libstdc++
# parses cleanly). Derived from the compiler path so it only fires for the snap
# clang; a native flutter (tarball) toolchain is left untouched. Disable with
# -DHORALOCA_NO_GCC_TOOLCHAIN=ON.
if(CMAKE_CXX_COMPILER MATCHES "/snap/flutter/" AND NOT HORALOCA_NO_GCC_TOOLCHAIN)
  get_filename_component(_HL_BIN "${CMAKE_CXX_COMPILER}" DIRECTORY)  # <snap>/usr/bin
  get_filename_component(_HL_USR "${_HL_BIN}" DIRECTORY)             # <snap>/usr
  if(EXISTS "${_HL_USR}/include/c++")
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} --gcc-toolchain=${_HL_USR}")
    set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} --gcc-toolchain=${_HL_USR}")
    message(STATUS "horaloca: redirecting clang libstdc++ to snap toolchain ${_HL_USR}")
  endif()
endif()

# The name of the executable created for the application. Change as needed.
set(BINARY_NAME "horaloca")
# The unique GTK application identifier for this application. See:
# https://wiki.gnome.org/HowDoI/ChooseApplicationID
set(APPLICATION_ID "com.beriberikix.horaloca")

cmake_policy(VERSION 3.13...3.27)

# Root filesystem for cross-building.
if(FLUTTER_TARGET_PLATFORM_SYSROOT)
  set(CMAKE_SYSROOT ${FLUTTER_TARGET_PLATFORM_SYSROOT})
  set(CMAKE_FIND_ROOT_PATH ${CMAKE_SYSROOT})
endif()

# Configure build options.
get_property(IS_MULTICONFIG GLOBAL PROPERTY GENERATOR_IS_MULTI_CONFIG)
if(IS_MULTICONFIG)
  set(CMAKE_CONFIGURATION_TYPES "Debug;Profile;Release"
    CACHE STRING "" FORCE)
else()
  if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE "Debug" CACHE
      STRING "Flutter build mode" FORCE)
    set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS
      "Debug" "Profile" "Release")
  endif()
endif()
# Has the same effect as setting CMAKE_BUILD_TYPE for single-config generators.
set(CMAKE_MAP_IMPORTED_CONFIG_PROFILE "Release")

# Use ${BINARY_NAME} as the target for the executable.
set(FLUTTER_TARGET_PLATFORM linux-x64)

# Define build configuration options.
if(NOT IS_MULTICONFIG)
  set_property(GLOBAL PROPERTY PREDEFINED_TARGETS_FOLDER "Predefined")
endif()

# Compilation settings that should be applied to most targets.
function(APPLY_STANDARD_SETTINGS TARGET)
  target_compile_features(${TARGET} PUBLIC cxx_std_14)
  target_compile_options(${TARGET} PRIVATE -Wall -Werror)
  # tray_manager (and other AppIndicator-based plugins) call the deprecated
  # Canonical app_indicator_* API. Combined with -Werror that fails the build,
  # even though the code is correct. This function is invoked by every plugin's
  # CMakeLists (it is defined here, in the app), so downgrading just this one
  # diagnostic to a warning unblocks them all without editing generated files.
  target_compile_options(${TARGET} PRIVATE -Wno-error=deprecated-declarations)
  target_compile_options(${TARGET} PRIVATE "$<$<NOT:$<CONFIG:Debug>>:-O3>")
  target_compile_definitions(${TARGET} PRIVATE "$<$<NOT:$<CONFIG:Debug>>:NDEBUG>")
endfunction()

# Flutter library and tool build rules.
set(FLUTTER_MANAGED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/flutter")
add_subdirectory(${FLUTTER_MANAGED_DIR})

# System-level dependencies.
find_package(PkgConfig REQUIRED)
pkg_check_modules(GTK REQUIRED IMPORTED_TARGET gtk+-3.0)

add_definitions(-DAPPLICATION_ID="${APPLICATION_ID}")

# Application build; see runner/CMakeLists.txt.
add_subdirectory("runner")

# horaloca's native video subproject (depends on the `flutter` and GTK targets
# defined above).
add_subdirectory("horaloca_video")

# Run the Flutter tool portions of the build.
include(flutter/generated_plugins.cmake)

# Only the install-bundle pieces below differ per-app; kept aligned with the
# stock template.
set(BUILD_BUNDLE_DIR "${PROJECT_BINARY_DIR}/bundle")
if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
  set(CMAKE_INSTALL_PREFIX "${BUILD_BUNDLE_DIR}" CACHE PATH "..." FORCE)
endif()

# Strip the binary release builds to reduce size.
if(CMAKE_BUILD_TYPE STREQUAL "Release")
  install(CODE "execute_process(COMMAND strip -s -x \"${CMAKE_INSTALL_PREFIX}/${BINARY_NAME}\")")
endif()

set(INSTALL_BUNDLE_DATA_DIR "${CMAKE_INSTALL_PREFIX}/data")
set(INSTALL_BUNDLE_LIB_DIR "${CMAKE_INSTALL_PREFIX}/lib")

install(TARGETS ${BINARY_NAME} RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_ICU_DATA_FILE}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

foreach(bundled_library ${PLUGIN_BUNDLED_LIBRARIES})
  install(FILES "${bundled_library}"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endforeach(bundled_library)

# Fully re-copy the assets directory on each build to avoid having stale files
# from a previous install.
set(FLUTTER_ASSET_DIR_NAME "flutter_assets")
install(CODE "
  file(REMOVE_RECURSE \"${INSTALL_BUNDLE_DATA_DIR}/${FLUTTER_ASSET_DIR_NAME}\")
  " COMPONENT Runtime)
install(DIRECTORY "${PROJECT_BUILD_DIR}/${FLUTTER_ASSET_DIR_NAME}"
  DESTINATION "${INSTALL_BUNDLE_DATA_DIR}" COMPONENT Runtime)

# Install the AOT library on non-Debug builds only.
if(NOT CMAKE_BUILD_TYPE STREQUAL "Debug")
  install(FILES "${AOT_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endif()
