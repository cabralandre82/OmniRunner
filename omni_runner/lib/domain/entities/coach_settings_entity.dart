import 'package:equatable/equatable.dart';

/// User preferences for the audio coach.
///
/// Each flag controls whether a specific category of voice
/// announcement is enabled during a workout session.
///
/// Immutable value object. No logic. No behavior.
final class CoachSettingsEntity extends Equatable {
  /// Announce every km completed (distance trigger).
  final bool kmEnabled;

  /// Announce when the runner passes or is passed by the ghost.
  final bool ghostEnabled;

  /// Periodic time-based announcements (e.g., every 5 min).
  final bool periodicEnabled;

  /// Announce heart-rate zone changes via TTS.
  final bool hrZoneEnabled;

  /// User's maximum heart rate for zone calculation.
  ///
  /// Defaults to 190 (a reasonable mid-range value).
  /// Can be customised via settings or derived from `220 - age`.
  final int maxHr;

  /// Use imperial units (miles) instead of metric (km).
  final bool useImperial;

  /// Whether the user's profile is visible in public rankings.
  final bool profileVisibleInRanking;

  /// Whether the user's runs appear in the assessoria feed.
  final bool shareActivityInFeed;

  const CoachSettingsEntity({
    this.kmEnabled = true,
    this.ghostEnabled = true,
    this.periodicEnabled = true,
    this.hrZoneEnabled = true,
    this.maxHr = 190,
    this.useImperial = false,
    this.profileVisibleInRanking = true,
    this.shareActivityInFeed = true,
  });

  /// Create a copy with optional overrides.
  CoachSettingsEntity copyWith({
    bool? kmEnabled,
    bool? ghostEnabled,
    bool? periodicEnabled,
    bool? hrZoneEnabled,
    int? maxHr,
    bool? useImperial,
    bool? profileVisibleInRanking,
    bool? shareActivityInFeed,
  }) =>
      CoachSettingsEntity(
        kmEnabled: kmEnabled ?? this.kmEnabled,
        ghostEnabled: ghostEnabled ?? this.ghostEnabled,
        periodicEnabled: periodicEnabled ?? this.periodicEnabled,
        hrZoneEnabled: hrZoneEnabled ?? this.hrZoneEnabled,
        maxHr: maxHr ?? this.maxHr,
        useImperial: useImperial ?? this.useImperial,
        profileVisibleInRanking:
            profileVisibleInRanking ?? this.profileVisibleInRanking,
        shareActivityInFeed:
            shareActivityInFeed ?? this.shareActivityInFeed,
      );

  @override
  List<Object?> get props => [
        kmEnabled,
        ghostEnabled,
        periodicEnabled,
        hrZoneEnabled,
        maxHr,
        useImperial,
        profileVisibleInRanking,
        shareActivityInFeed,
      ];
}
