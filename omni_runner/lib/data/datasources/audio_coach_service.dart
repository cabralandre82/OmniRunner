import 'dart:io' show Platform;

import 'package:flutter_tts/flutter_tts.dart';
import 'package:omni_runner/core/logging/logger.dart';

/// Low-level datasource wrapping [FlutterTts].
///
/// Handles engine init (language, rate, volume) and raw text speaking.
/// Queue/priority logic lives in the repository layer.
class AudioCoachService {
  static const _tag = 'AudioCoach';

  FlutterTts? _tts;
  bool _speaking = false;

  /// Whether TTS is currently speaking.
  bool get isSpeaking => _speaking;

  /// Initialise the TTS engine.
  ///
  /// [language] defaults to `pt-BR`. [rate] 0.0–1.0 (default 0.5).
  /// [volume] 0.0–1.0 (default 1.0). Idempotent.
  Future<void> init({
    String language = 'pt-BR',
    double rate = 0.5,
    double volume = 1.0,
  }) async {
    if (_tts != null) return;
    try {
      final tts = FlutterTts();
      await tts.setLanguage(language);
      await tts.setSpeechRate(rate);
      await tts.setVolume(volume);
      if (Platform.isIOS) {
        await tts.setSharedInstance(true);
        await tts.setIosAudioCategory(
          IosTextToSpeechAudioCategory.playback,
          [
            IosTextToSpeechAudioCategoryOptions.duckOthers,
            IosTextToSpeechAudioCategoryOptions.mixWithOthers,
          ],
          IosTextToSpeechAudioMode.voicePrompt,
        );
      }
      await tts.awaitSpeakCompletion(true);
      tts.setStartHandler(() => _speaking = true);
      tts.setCompletionHandler(() => _speaking = false);
      tts.setErrorHandler((_) => _speaking = false);
      tts.setCancelHandler(() => _speaking = false);
      _tts = tts;
    } on Exception catch (e) {
      AppLogger.error('TTS init failed — voice coaching disabled', tag: _tag, error: e);
    }
  }

  /// Speak [text] and return a future that completes when done.
  Future<void> speak(String text) async {
    if (_tts == null || text.isEmpty) return;
    try {
      await _tts!.speak(text);
    } on Exception catch (e) {
      AppLogger.warn('TTS speak failed: $e', tag: _tag);
      _speaking = false;
    }
  }

  /// Stop any ongoing speech immediately.
  Future<void> stop() async {
    if (_tts == null) return;
    try {
      await _tts!.stop();
    } on Exception catch (e) {
      AppLogger.warn('TTS stop failed: $e', tag: _tag);
    }
    _speaking = false;
  }

  /// Release TTS resources.
  Future<void> dispose() async {
    await stop();
    _tts = null;
  }
}
