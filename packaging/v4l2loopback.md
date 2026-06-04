# Configuring the `v4l2loopback` virtual camera

horaloca outputs its overlaid feed to a **virtual** V4L2 device created by the
`v4l2loopback` kernel module. Because the module runs in kernel space, it must
be installed and loaded on the **host** — a confined snap cannot load it.

## 1. Install the module

```bash
sudo apt update
sudo apt install v4l2loopback-dkms v4l2loopback-utils
```

DKMS rebuilds the module automatically on kernel upgrades.

## 2. Load it (one-off)

```bash
sudo modprobe v4l2loopback \
    video_nr=10 \
    card_label="horaloca Virtual Camera" \
    exclusive_caps=1
```

* `video_nr=10` — create the device at a predictable path, `/dev/video10`.
  (Pick any free number; horaloca auto-detects by driver/label, not by number.)
* `card_label="horaloca Virtual Camera"` — the friendly name apps show in their
  camera picker. horaloca also uses the loopback **driver string** to identify
  the sink, so the label is for humans.
* `exclusive_caps=1` — **required**. Makes the device advertise CAPTURE-only to
  consumers (Chrome/Zoom ignore devices that advertise both OUTPUT and CAPTURE).

Verify:

```bash
v4l2-ctl --list-devices
# horaloca Virtual Camera (platform:v4l2loopback-000):
#         /dev/video10
```

## 3. Make it persistent across reboots

```bash
# Load the module at boot.
echo v4l2loopback | sudo tee /etc/modules-load.d/v4l2loopback.conf

# Pass the same options every time it loads.
sudo tee /etc/modprobe.d/v4l2loopback.conf >/dev/null <<'EOF'
options v4l2loopback video_nr=10 card_label="horaloca Virtual Camera" exclusive_caps=1
EOF
```

## 4. Unload (to remove / reconfigure)

```bash
sudo modprobe -r v4l2loopback
```

## Troubleshooting

* **No `/dev/video10` after modprobe** — check `dmesg | tail`; a kernel/headers
  mismatch will make DKMS fail to build. `sudo apt install linux-headers-$(uname -r)`.
* **App doesn't list the camera** — almost always missing `exclusive_caps=1`.
* **`modprobe: FATAL: Module v4l2loopback not found`** — the DKMS build failed;
  reinstall `v4l2loopback-dkms` and re-check headers.
