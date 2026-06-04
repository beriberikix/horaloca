import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../app/app_controller.dart';
import '../app/app_state.dart';

/// MVP settings/status window.
///
/// It is normally hidden (the app lives in the tray). For MVP it just shows the
/// pipeline status, the detected timezone, and the current overlay preview text
/// so the user can confirm things are working. It is built as the Phase 2 shell:
/// the position grid, font picker, and PNG-background picker drop in here,
/// each writing through [AppController.updateConfig].
class SettingsWindow extends StatelessWidget {
  const SettingsWindow({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('horaloca'),
        actions: <Widget>[
          // Closing the window hides it (the tray keeps the app alive).
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Hide to tray',
            onPressed: () => windowManager.hide(),
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: controller,
        builder: (BuildContext context, _) {
          final AppState state = controller.state;
          return Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _StatusRow(state: state),
                const SizedBox(height: 12),
                Text('Timezone: ${state.timezoneName}'),
                const SizedBox(height: 12),
                _OverlayPreview(text: controller.config.text),
                if (state.status == PipelineStatus.error &&
                    state.errorMessage != null) ...<Widget>[
                  const SizedBox(height: 12),
                  Text(
                    state.errorMessage!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ],
                const Spacer(),
                Row(
                  children: <Widget>[
                    FilledButton(
                      onPressed: controller.toggleRunning,
                      child: Text(state.isRunning ? 'Stop' : 'Start'),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton(
                      onPressed: controller.refreshTimezone,
                      child: const Text('Refresh Timezone'),
                    ),
                  ],
                ),
                // TODO(phase2): position grid, font picker, scale slider, and
                // PNG-background picker go here — each calling
                // controller.updateConfig(...).
              ],
            ),
          );
        },
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final Color color = switch (state.status) {
      PipelineStatus.running => Colors.green,
      PipelineStatus.error => Colors.red,
      PipelineStatus.starting => Colors.orange,
      PipelineStatus.stopped => Colors.grey,
    };
    return Row(
      children: <Widget>[
        Icon(Icons.circle, size: 12, color: color),
        const SizedBox(width: 8),
        Text('Status: ${state.status.label}',
            style: Theme.of(context).textTheme.titleMedium),
      ],
    );
  }
}

/// A small mock of how the badge looks, so the user can sanity-check styling
/// without opening a video call.
class _OverlayPreview extends StatelessWidget {
  const _OverlayPreview({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 80,
      decoration: BoxDecoration(
        color: Colors.blueGrey.shade700,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Align(
        alignment: Alignment.bottomLeft,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.55),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              text.isEmpty ? '--:-- (—)' : text,
              style: const TextStyle(
                color: Colors.white,
                fontFamily: 'Ubuntu',
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
