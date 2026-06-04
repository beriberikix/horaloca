import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:window_manager/window_manager.dart';

import '../app/app_controller.dart';
import '../app/app_state.dart';
import '../models/overlay_config.dart';
import '../models/overlay_position.dart';

/// Phase-2 settings window: live preview + controls for placement, format,
/// font, shape, border, and the three colours. Every change writes through
/// [AppController.updateConfig], which persists it and live-updates the
/// virtual camera. Normally hidden; opened from the tray "Settings…" item.
class SettingsWindow extends StatefulWidget {
  const SettingsWindow({super.key, required this.controller});

  final AppController controller;

  @override
  State<SettingsWindow> createState() => _SettingsWindowState();
}

class _SettingsWindowState extends State<SettingsWindow> {
  AppController get _c => widget.controller;

  List<String> _fonts = const <String>[];

  @override
  void initState() {
    super.initState();
    _loadFonts();
  }

  Future<void> _loadFonts() async {
    final List<String> fonts = await _c.listFonts();
    if (mounted) setState(() => _fonts = fonts);
  }

  // Apply a single-field edit to the live config.
  void _update(OverlayConfig cfg) => _c.updateConfig(cfg);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('horaloca settings'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Hide to tray',
            onPressed: () => windowManager.hide(),
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: _c,
        builder: (BuildContext context, _) {
          final OverlayConfig cfg = _c.config;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              _PreviewCard(config: cfg),
              const SizedBox(height: 16),
              _statusRow(),
              const Divider(height: 32),
              _sectionTitle('Placement'),
              _placementGrid(cfg),
              const Divider(height: 32),
              _sectionTitle('Format'),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('24-hour clock'),
                value: cfg.use24HourClock,
                onChanged: (bool v) =>
                    _update(cfg.copyWith(use24HourClock: v)),
              ),
              const SizedBox(height: 8),
              _fontPicker(cfg),
              const SizedBox(height: 8),
              _scaleSlider(cfg),
              const Divider(height: 32),
              _sectionTitle('Shape'),
              _shapeControls(cfg),
              const Divider(height: 32),
              _sectionTitle('Colours'),
              _colorRow('Text', cfg.textColor,
                  (int c) => _update(cfg.copyWith(textColor: c))),
              _colorRow('Background', cfg.backgroundColor,
                  (int c) => _update(cfg.copyWith(backgroundColor: c))),
              _colorRow('Border', cfg.borderColor,
                  (int c) => _update(cfg.copyWith(borderColor: c))),
              const SizedBox(height: 16),
            ],
          );
        },
      ),
    );
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text, style: Theme.of(context).textTheme.titleMedium),
      );

  Widget _statusRow() {
    final AppState s = _c.state;
    final Color color = switch (s.status) {
      PipelineStatus.running => Colors.green,
      PipelineStatus.error => Colors.red,
      PipelineStatus.starting => Colors.orange,
      PipelineStatus.stopped => Colors.grey,
    };
    return Row(
      children: <Widget>[
        Icon(Icons.circle, size: 12, color: color),
        const SizedBox(width: 8),
        Text('Status: ${s.status.label}'),
        const Spacer(),
        FilledButton(
          onPressed: _c.toggleRunning,
          child: Text(s.isRunning ? 'Stop' : 'Start'),
        ),
      ],
    );
  }

  Widget _placementGrid(OverlayConfig cfg) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        for (final OverlayPosition p in OverlayPosition.values)
          SizedBox(
            width: 84,
            height: 40,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                padding: EdgeInsets.zero,
                backgroundColor: p == cfg.position
                    ? Theme.of(context).colorScheme.primaryContainer
                    : null,
              ),
              onPressed: () => _update(cfg.copyWith(position: p)),
              child: Icon(_iconForPosition(p), size: 18),
            ),
          ),
      ],
    );
  }

  IconData _iconForPosition(OverlayPosition p) {
    switch (p) {
      case OverlayPosition.topLeft:
        return Icons.north_west;
      case OverlayPosition.topCenter:
        return Icons.north;
      case OverlayPosition.topRight:
        return Icons.north_east;
      case OverlayPosition.centerLeft:
        return Icons.west;
      case OverlayPosition.center:
        return Icons.center_focus_strong;
      case OverlayPosition.centerRight:
        return Icons.east;
      case OverlayPosition.bottomLeft:
        return Icons.south_west;
      case OverlayPosition.bottomCenter:
        return Icons.south;
      case OverlayPosition.bottomRight:
        return Icons.south_east;
    }
  }

  Widget _fontPicker(OverlayConfig cfg) {
    // Make sure the current family is selectable even if the list is still
    // loading or doesn't include it.
    final List<String> items = <String>{
      cfg.fontFamily,
      ..._fonts,
    }.toList();
    return Row(
      children: <Widget>[
        const SizedBox(width: 80, child: Text('Font')),
        Expanded(
          child: DropdownButton<String>(
            isExpanded: true,
            value: cfg.fontFamily,
            items: <DropdownMenuItem<String>>[
              for (final String f in items)
                DropdownMenuItem<String>(value: f, child: Text(f)),
            ],
            onChanged: (String? f) {
              if (f != null) _update(cfg.copyWith(fontFamily: f));
            },
          ),
        ),
      ],
    );
  }

  Widget _scaleSlider(OverlayConfig cfg) {
    return Row(
      children: <Widget>[
        const SizedBox(width: 80, child: Text('Size')),
        Expanded(
          child: Slider(
            min: 0.5,
            max: 2.5,
            divisions: 20,
            label: '${cfg.fontScale.toStringAsFixed(2)}×',
            value: cfg.fontScale.clamp(0.5, 2.5),
            onChanged: (double v) => _update(cfg.copyWith(fontScale: v)),
          ),
        ),
      ],
    );
  }

  Widget _shapeControls(OverlayConfig cfg) {
    final bool rounded = cfg.cornerRadius > 0;
    final bool border = cfg.borderWidth > 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            const SizedBox(width: 80, child: Text('Corners')),
            SegmentedButton<bool>(
              segments: const <ButtonSegment<bool>>[
                ButtonSegment<bool>(value: false, label: Text('Square')),
                ButtonSegment<bool>(value: true, label: Text('Rounded')),
              ],
              selected: <bool>{rounded},
              onSelectionChanged: (Set<bool> s) =>
                  _update(cfg.copyWith(cornerRadius: s.first ? 12.0 : 0.0)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            const SizedBox(width: 80, child: Text('Border')),
            SegmentedButton<bool>(
              segments: const <ButtonSegment<bool>>[
                ButtonSegment<bool>(value: false, label: Text('None')),
                ButtonSegment<bool>(value: true, label: Text('1 px')),
              ],
              selected: <bool>{border},
              onSelectionChanged: (Set<bool> s) =>
                  _update(cfg.copyWith(borderWidth: s.first ? 1.0 : 0.0)),
            ),
          ],
        ),
      ],
    );
  }

  Widget _colorRow(String label, int argb, ValueChanged<int> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: <Widget>[
          SizedBox(width: 96, child: Text(label)),
          InkWell(
            onTap: () => _pickColor(label, argb, onChanged),
            child: Container(
              width: 48,
              height: 28,
              decoration: BoxDecoration(
                color: Color(argb),
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text('#${argb.toRadixString(16).padLeft(8, '0').toUpperCase()}',
              style: const TextStyle(fontFeatures: <FontFeature>[])),
        ],
      ),
    );
  }

  Future<void> _pickColor(
      String label, int argb, ValueChanged<int> onChanged) async {
    Color picked = Color(argb);
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text('$label colour'),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: Color(argb),
            enableAlpha: true,
            labelTypes: const <ColorLabelType>[ColorLabelType.rgb],
            onColorChanged: (Color c) => picked = c,
          ),
        ),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Select')),
        ],
      ),
    );
    if (ok == true) onChanged(picked.toARGB32());
  }
}

/// A best-effort Flutter mock of the burned-in badge so the user can preview
/// styling without opening a call. The authoritative render is the native
/// Cairo pipeline (the virtual camera updates live too).
class _PreviewCard extends StatelessWidget {
  const _PreviewCard({required this.config});

  final OverlayConfig config;

  @override
  Widget build(BuildContext context) {
    final Alignment align = Alignment(
      config.position.horizontalAnchor * 2 - 1,
      config.position.verticalAnchor * 2 - 1,
    );
    final String txt = config.text.isEmpty ? '--:--\n— (—)' : config.text;
    final int nl = txt.indexOf('\n');
    final String timeLine = nl == -1 ? txt : txt.substring(0, nl);
    final String tzLine = nl == -1 ? '' : txt.substring(nl + 1);
    final double base = 14 * config.fontScale.clamp(0.6, 1.6);
    return Container(
      height: 150,
      decoration: BoxDecoration(
        color: Colors.blueGrey.shade800,
        borderRadius: BorderRadius.circular(6),
      ),
      padding: const EdgeInsets.all(10),
      child: Align(
        alignment: align,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Color(config.backgroundColor),
            borderRadius: BorderRadius.circular(config.cornerRadius),
            border: config.borderWidth > 0
                ? Border.all(
                    color: Color(config.borderColor),
                    width: config.borderWidth)
                : null,
          ),
          child: Text.rich(
            TextSpan(
              children: <InlineSpan>[
                TextSpan(text: timeLine, style: TextStyle(fontSize: base)),
                if (tzLine.isNotEmpty)
                  TextSpan(
                      text: '\n$tzLine',
                      style: TextStyle(fontSize: base * 0.72)),
              ],
            ),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(config.textColor),
              fontFamily: config.fontFamily,
              fontWeight: FontWeight.bold,
              height: 1.1,
            ),
          ),
        ),
      ),
    );
  }
}
