/// Status of a workout session.
///
/// Transitions: [initial] -> [running] -> [paused] -> [running] -> [completed]
///                                     |-> [completed]
///                                     |-> [discarded]
enum WorkoutStatus {
  /// Session created but not yet started.
  initial,

  /// Session actively recording GPS data.
  running,

  /// Session temporarily paused by user.
  paused,

  /// Session finished normally.
  completed,

  /// Session discarded by user or system.
  discarded,
}
