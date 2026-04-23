/// Locale vocabularies understood by the audio coach subsystem.
///
/// Distinct from the UI-facing [AppLocalizations] locales because the
/// audio coach targets the on-device TTS engine and must map to a
/// BCP-47 tag accepted by `flutter_tts.setLanguage(...)`.
///
/// Finding reference: L22-06 (Voice coaching parcial).
enum AudioCoachLocale {
  /// Brazilian Portuguese. Default, matches the L10-07 primary market.
  ptBR('pt-BR'),

  /// English (US). Covers international amateur runners.
  en('en-US'),

  /// Spanish (Spain/LatAm). Covers broader LatAm reach goal.
  es('es-ES');

  const AudioCoachLocale(this.languageTag);

  /// BCP-47 tag fed directly into `flutter_tts.setLanguage(...)`.
  final String languageTag;

  /// Resolve a free-form `ptBR`/`pt_BR`/`pt-BR`/`pt` string into a
  /// canonical locale.
  ///
  /// Unknown tags fall back to [AudioCoachLocale.ptBR] (primary market)
  /// rather than throwing — voice coaching must never crash the session.
  /// A non-matching locale still speaks, just not in the requested tongue.
  static AudioCoachLocale fromTag(String? raw) {
    if (raw == null || raw.isEmpty) return AudioCoachLocale.ptBR;
    final normalized = raw.toLowerCase().replaceAll('_', '-');
    if (normalized.startsWith('pt')) return AudioCoachLocale.ptBR;
    if (normalized.startsWith('en')) return AudioCoachLocale.en;
    if (normalized.startsWith('es')) return AudioCoachLocale.es;
    return AudioCoachLocale.ptBR;
  }
}
