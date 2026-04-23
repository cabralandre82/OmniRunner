import 'dart:io' show Platform;

import 'package:flutter_tts/flutter_tts.dart';
import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/domain/value_objects/audio_coach_locale.dart';

/// Low-level datasource wrapping [FlutterTts].
///
/// Handles engine init (language, rate, volume) and raw text speaking.
/// Queue/priority logic lives in the repository layer.
///
/// L22-06: accepts an [AudioCoachLocale] at init time and exposes
/// [setLocale] so the locale can be swapped mid-session (e.g., user
/// toggles language in settings).
class AudioCoachService {
  static const _tag = 'AudioCoach';

  FlutterTts? _tts;
  bool _speaking = false;
  AudioCoachLocale _locale = AudioCoachLocale.ptBR;

  /// Whether TTS is currently speaking.
  bool get isSpeaking => _speaking;

  /// The locale currently configured on the TTS engine.
  AudioCoachLocale get locale => _locale;

  /// Initialise the TTS engine.
  ///
  /// [locale] defaults to [AudioCoachLocale.ptBR]. [rate] 0.0–1.0
  /// (default 0.5). [volume] 0.0–1.0 (default 1.0). Idempotent.
  Future<void> init({
    AudioCoachLocale locale = AudioCoachLocale.ptBR,
    double rate = 0.5,
    double volume = 1.0,
  }) async {
    if (_tts != null) return;
    try {
      final tts = FlutterTts();
      await tts.setLanguage(locale.languageTag);
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
      _locale = locale;
    } on Exception catch (e) {
      AppLogger.error('TTS init failed — voice coaching disabled', tag: _tag, error: e);
    }
  }

  /// Swap the engine locale mid-session. No-op if init hasn't run
  /// (swap is applied on next init).
  Future<void> setLocale(AudioCoachLocale locale) async {
    _locale = locale;
    final tts = _tts;
    if (tts == null) return;
    try {
      await tts.setLanguage(locale.languageTag);
    } on Exception catch (e) {
      AppLogger.warn('TTS setLanguage failed: $e', tag: _tag);
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
