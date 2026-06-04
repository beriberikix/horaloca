/// Lifecycle state of the native video pipeline.
///
/// Emitted by the native plugin over the status [EventChannel] and surfaced in
/// the tray menu's "Status" line.
enum PipelineStatus {
  /// Pipeline not running (initial state, or after a clean stop).
  stopped,

  /// Pipeline is starting up (negotiating caps with the cameras).
  starting,

  /// Pipeline running: physical cam → overlay → virtual cam.
  running,

  /// Pipeline hit an error and is not running. See [AppState.errorMessage].
  error;

  /// Human-readable label for the tray "Status" item.
  String get label {
    switch (this) {
      case PipelineStatus.stopped:
        return 'Stopped';
      case PipelineStatus.starting:
        return 'Starting…';
      case PipelineStatus.running:
        return 'Running';
      case PipelineStatus.error:
        return 'Error';
    }
  }

  /// Parse the string the native side sends on the status channel.
  static PipelineStatus fromWire(String? value) {
    return PipelineStatus.values.firstWhere(
      (s) => s.name == value,
      orElse: () => PipelineStatus.stopped,
    );
  }
}

/// Immutable snapshot of the whole app's observable state.
///
/// Held by [AppController]; the tray and the (future) settings window render
/// from this.
class AppState {
  const AppState({
    this.status = PipelineStatus.stopped,
    this.errorMessage,
    this.timezoneName = '',
  });

  final PipelineStatus status;

  /// Populated only when [status] == [PipelineStatus.error].
  final String? errorMessage;

  /// Currently detected IANA timezone name, e.g. `America/Los_Angeles`.
  /// Shown for context and refreshed by the tray's "Refresh Timezone" action.
  final String timezoneName;

  bool get isRunning => status == PipelineStatus.running;

  AppState copyWith({
    PipelineStatus? status,
    String? errorMessage,
    bool clearError = false,
    String? timezoneName,
  }) {
    return AppState(
      status: status ?? this.status,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      timezoneName: timezoneName ?? this.timezoneName,
    );
  }
}
