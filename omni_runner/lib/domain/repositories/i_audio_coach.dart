import 'package:omni_runner/domain/entities/audio_event_entity.dart';

/// Contract for the audio coaching engine.
///
/// Domain interface — implementation lives in infrastructure/data layer.
/// Responsible for initialising the TTS engine, speaking coaching events,
/// and releasing resources.
///
/// Dependency direction: data/infrastructure -> domain (implements this).
abstract interface class IAudioCoach {
  /// Initialise the TTS engine and any required resources.
  ///
  /// Must be called once before [speak]. Implementations should be
  /// idempotent (calling init twice is safe).
  Future<void> init();

  /// Enqueue or immediately speak an [event].
  ///
  /// The implementation decides whether to queue, interrupt, or drop
  /// the event based on [AudioEventEntity.priority] and current state.
  Future<void> speak(AudioEventEntity event);

  /// Release TTS resources.
  ///
  /// After calling dispose, [speak] must not be called until [init]
  /// is invoked again.
  Future<void> dispose();
}
