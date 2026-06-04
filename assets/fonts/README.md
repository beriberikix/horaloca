# Fonts

The burned-in overlay is rendered natively via **Pango/Cairo**, which resolves
the `Ubuntu` font family through **fontconfig** — preinstalled on Ubuntu and
provided by the `gnome` snap extension. So no font is bundled by default.

To pin the exact glyphs regardless of host, drop the TTFs here:

```
assets/fonts/Ubuntu-Regular.ttf
assets/fonts/Ubuntu-Bold.ttf
```

and re-enable the commented `fonts:` section in `pubspec.yaml`. The Ubuntu font
ships at `/usr/share/fonts/truetype/ubuntu/` on most Ubuntu installs:

```bash
cp /usr/share/fonts/truetype/ubuntu/Ubuntu-{R,B}.ttf assets/fonts/
# then rename to Ubuntu-Regular.ttf / Ubuntu-Bold.ttf
```
