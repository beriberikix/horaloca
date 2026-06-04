# horaloca

> **hora loca** — "crazy hour." A passive courtesy clock for distributed teams.

`horaloca` taps your physical webcam, burns a highly readable **local time +
timezone** badge into the corner of the feed, and republishes it as a **virtual
webcam** that Zoom, Google Meet, Slack and friends can select. It's a gentle,
slightly tongue-in-cheek reminder to colleagues that it might be the middle of
the night for you.

It runs quietly in the **system tray** — no window to babysit.

```
┌─────────────────────────────────┐
│                                 │
│         (your webcam)           │
│                                 │
│  ┌───────────────┐              │
│  │ 03:45 AM (PST)│   ← badge    │
│  └───────────────┘              │
└─────────────────────────────────┘
```

- **Platform:** Ubuntu Linux desktop (modern LTS), X11 or Wayland.
- **Pipeline:** GStreamer (`v4l2src → cairooverlay → v4l2sink`), all native.
- **UI:** Flutter (Linux desktop) + AppIndicator system tray.

---

## How it works (architecture)

Flutter owns the **tray, lifecycle, and (future) settings UI**. It never touches
raw video frames. All video work happens natively in a small C++ integration
linked into the Flutter Linux runner:

```
Flutter (Dart)                         Native C++ (linux/horaloca_video/)
  ClockService  ── 1 Hz time string ─▶  ┐
  TrayService   ── start/stop ────────▶ │ MethodChannel  "horaloca/video"
  AppController ── overlay config ────▶ ┘ EventChannel    "horaloca/video/status"
                                          │
                                          ▼
        v4l2src(/dev/video0) ! videoconvert ! cairooverlay ! videoconvert
                             ! videoscale ! capsfilter(YUY2) ! v4l2sink(/dev/video10)
                                          │
                                   Cairo draw callback paints the badge
```

Once per second `ClockService` sends an updated string across the method
channel; the native `OverlayRenderer` swaps it under a lock and the next frame
shows the new time. The pipeline never restarts.

| Layer | Files |
|-------|-------|
| Dart models | `lib/models/overlay_config.dart`, `lib/models/overlay_position.dart` |
| Dart services | `lib/services/{clock_service,tray_service,video_pipeline_bridge}.dart` |
| Dart app/state | `lib/app/{app_controller,app_state}.dart`, `lib/main.dart` |
| Native pipeline | `linux/horaloca_video/{pipeline_controller,overlay_renderer,overlay_model,horaloca_video_plugin}.{cc,h}` |

---

## Prerequisites

### 1. The virtual camera (`v4l2loopback`)

This is required and lives on the **host** (a snap can't load kernel modules).

```bash
sudo apt install v4l2loopback-dkms v4l2loopback-utils
sudo modprobe v4l2loopback video_nr=10 \
    card_label="horaloca Virtual Camera" exclusive_caps=1
```

`exclusive_caps=1` is **mandatory** so apps see it as a real capture camera.
Full setup (incl. making it persistent) → [`packaging/v4l2loopback.md`](packaging/v4l2loopback.md).

### 2. Build toolchain (for building from source)

```bash
# Flutter (Linux desktop)
sudo snap install flutter --classic
flutter config --enable-linux-desktop

# Native pipeline build deps
sudo apt install \
  clang cmake ninja-build pkg-config \
  libgtk-3-dev \
  libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev \
  gstreamer1.0-plugins-base gstreamer1.0-plugins-good \
  libcairo2-dev libpango1.0-dev \
  libayatana-appindicator3-dev
```

> The GStreamer **runtime** plugins (`gstreamer1.0-plugins-base/good`) provide
> `v4l2src`, `v4l2sink`, `videoconvert`, `videoscale`, `cairooverlay` and
> `textoverlay`. They are also staged into the snap.

---

## Build & run (development)

```bash
flutter pub get
flutter run -d linux        # debug, attached
# or a release binary:
flutter build linux --release
./build/linux/x64/release/bundle/horaloca
```

On launch the window stays hidden and a **clock icon** appears in the system
tray. Left- or right-click it for: **Status (Running/Stopped)**,
**Refresh Timezone**, **Quit**.

> On GNOME Shell you need the **AppIndicator/KStatusNotifier** extension enabled
> for the tray icon to appear (Ubuntu's default session already has it).

> **Toolchain note (bleeding-edge hosts).** The native pipeline links the
> host's GStreamer. The Flutter **snap**'s bundled, confined toolchain (older
> glibc/glib) cannot link a much newer host GStreamer — on e.g. Ubuntu 25.10+/
> GCC 15 the link fails with `undefined reference to g_memdup2 / GLIBC_2.3x`.
> Two ways around it:
> 1. Install Flutter from the **official tarball/git** (uses your *host*
>    clang/gcc + ld) instead of the snap, then `flutter run -d linux` works.
> 2. Build the snap with **`snapcraft`** (below) — it builds in a self-consistent
>    core24 container, so versions always match. This is the validated path.
>
> `linux/CMakeLists.txt` already carries two scoped workarounds so the Flutter
> *snap* at least **compiles** here: it downgrades the AppIndicator
> `-Wdeprecated-declarations` from error, and redirects the snap clang to its
> own bundled libstdc++ (`--gcc-toolchain`) to dodge a GCC-15 `<new>` parse bug.

---

## Test it end-to-end

1. **Unit tests** (pure Dart, no hardware):

   ```bash
   flutter test
   ```

   Covers timezone/format logic (`03:45 AM (PST)`, `16:20 (CEST)`) and the
   overlay config/position model.

2. **Pipeline smoke test** (no Flutter — proves GStreamer + loopback work):

   ```bash
   gst-launch-1.0 v4l2src device=/dev/video0 ! videoconvert \
     ! cairooverlay ! videoconvert ! videoscale \
     ! video/x-raw,format=YUY2 ! v4l2sink device=/dev/video10 sync=false
   ```

   Then preview the virtual cam:

   ```bash
   ffplay /dev/video10        # or open it in Cheese / GNOME Snapshot
   ```

3. **Integration:** run horaloca, then in **Google Meet / Zoom / Slack** pick
   *"horaloca Virtual Camera"* as your camera. Confirm:
   - live video with the badge bottom-left,
   - the time advances every second,
   - tray **Status** flips Running ⇄ Stopped,
   - **Refresh Timezone** updates after `sudo timedatectl set-timezone <Zone>`,
   - **Quit** exits cleanly and frees the camera.

---

## Package as a snap

```bash
snapcraft                                   # builds horaloca_<version>_amd64.snap
sudo snap install ./horaloca_*.snap --dangerous
sudo snap connect horaloca:camera           # sideload-only (see below)
```

The snap bundles GStreamer + Cairo/Pango and the AppIndicator runtime. See
[`snap/snapcraft.yaml`](snap/snapcraft.yaml).

### Why the manual post-install steps?

They fall into two buckets — one is **sideload-only**, the other is **inherent
to any confined snap** (and is a one-time setup):

| Command | Needed because | Goes away when… |
|---|---|---|
| `snap install … --dangerous` | The `.snap` is unsigned/local, not from the Store. | Installing from the **Snap Store** (no flag needed). |
| `snap connect horaloca:camera` | Sideloaded snaps **auto-connect nothing**. | From the **Store**, `camera` **auto-connects** — no command. |
| `modprobe v4l2loopback …` | A confined snap **cannot load kernel modules** — it's a host kernel feature. | You make it **persistent once** (below); never type it again. |

So from the Store the only thing a user ever does is the **one-time**
v4l2loopback host setup. Make it permanent so it survives reboots:

```bash
echo v4l2loopback | sudo tee /etc/modules-load.d/v4l2loopback.conf
sudo tee /etc/modprobe.d/v4l2loopback.conf >/dev/null <<'EOF'
options v4l2loopback video_nr=10 card_label="horaloca Virtual Camera" exclusive_caps=1
EOF
```

After that the virtual camera is created automatically at every boot, and
horaloca starts streaming to it on launch. (Full details:
[`packaging/v4l2loopback.md`](packaging/v4l2loopback.md).)

---

## Roadmap (the architecture is already built for these)

The model (`OverlayConfig`) and native renderer already understand every option
below — Phase 2 is purely a settings-window UI that writes through
`AppController.updateConfig(...)`:

- **8-position perimeter grid** — `OverlayPosition` already defines all 9 slots.
- **Font family & scale** — already fields on `OverlayConfig`; the renderer uses
  them via Pango.
- **Custom PNG background** — the renderer already branches on
  `pngBackgroundPath`; just add a file picker.

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| App can't find a virtual camera | Load `v4l2loopback` with `exclusive_caps=1` (see above). |
| Meeting app doesn't list the cam | Missing `exclusive_caps=1`; reload the module. |
| Tray icon missing on GNOME | Enable the AppIndicator GNOME Shell extension. |
| "device busy" on start | Another app holds the physical cam; close it first. |
| Overlay text wrong timezone | Tray → **Refresh Timezone** (re-reads `/etc/localtime`). |

---

## License

Apache-2.0 — see [LICENSE](LICENSE).
