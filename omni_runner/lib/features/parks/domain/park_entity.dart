import 'package:equatable/equatable.dart';

/// A geographic point (latitude, longitude).
final class LatLng extends Equatable {
  final double lat;
  final double lng;
  const LatLng(this.lat, this.lng);

  @override
  List<Object?> get props => [lat, lng];
}

/// A known running park with a geographic polygon boundary.
///
/// Parks are seeded from OpenStreetMap `leisure=park` data for
/// Brazilian cities. The polygon is used for point-in-polygon
/// detection when a Strava activity syncs.
final class ParkEntity extends Equatable {
  final String id;
  final String name;
  final String city;
  final String state;

  /// Polygon boundary as ordered list of vertices.
  /// The last point implicitly connects to the first.
  final List<LatLng> polygon;

  /// Center point for map display and distance calculations.
  final LatLng center;

  /// Approximate area in square meters (for sorting).
  final double? areaSqM;

  const ParkEntity({
    required this.id,
    required this.name,
    required this.city,
    required this.state,
    required this.polygon,
    required this.center,
    this.areaSqM,
  });

  @override
  List<Object?> get props => [id, name, city, state, polygon, center];
}

/// Tier in the park leaderboard. Multiple categories give more people
/// a chance to be recognized, not just the fastest runner.
enum ParkLeaderboardTier {
  /// #1 of the week in any category.
  rei,

  /// Top 3.
  elite,

  /// Top 10.
  destaque,

  /// Top 20.
  pelotao,

  /// Ran at the park this period.
  frequentador,
}

/// Categories for park leaderboard rankings.
///
/// Each category has its own tier ladder, so a slow but consistent
/// runner can be "Rei da Frequência" while a fast runner is
/// "Rei do Pace". More categories = more winners = more engagement.
enum ParkLeaderboardCategory {
  /// Fastest average pace (single best run of the period).
  pace,

  /// Most distance accumulated in the period.
  distance,

  /// Most visits (unique days) in the period.
  frequency,

  /// Longest streak of consecutive days at this park.
  streak,

  /// Best pace improvement % vs. previous period.
  evolution,

  /// Longest single run at the park.
  longestRun,
}

/// A user's position in a park leaderboard for a specific category.
final class ParkLeaderboardEntry extends Equatable {
  final String parkId;
  final String userId;
  final String displayName;
  final ParkLeaderboardCategory category;
  final int rank;
  final ParkLeaderboardTier tier;

  /// The metric value (pace in sec/km, distance in meters, count, etc.)
  final double value;

  /// Period identifier (e.g. "2026-W09" for ISO week, "2026-02" for month).
  final String period;

  const ParkLeaderboardEntry({
    required this.parkId,
    required this.userId,
    required this.displayName,
    required this.category,
    required this.rank,
    required this.tier,
    required this.value,
    required this.period,
  });

  static ParkLeaderboardTier tierFromRank(int rank) {
    if (rank == 1) return ParkLeaderboardTier.rei;
    if (rank <= 3) return ParkLeaderboardTier.elite;
    if (rank <= 10) return ParkLeaderboardTier.destaque;
    if (rank <= 20) return ParkLeaderboardTier.pelotao;
    return ParkLeaderboardTier.frequentador;
  }

  @override
  List<Object?> get props =>
      [parkId, userId, category, rank, tier, value, period];
}

/// A recorded activity linked to a park.
final class ParkActivityEntity extends Equatable {
  final String id;
  final String parkId;
  final String userId;
  final String? displayName;

  /// Strava activity ID (nullable if from in-app tracking).
  final String? stravaActivityId;

  final double distanceM;
  final int movingTimeS;
  final int elapsedTimeS;
  final double? averagePaceSecPerKm;
  final double? averageHeartrate;
  final String? summaryPolyline;
  final DateTime startTime;
  final String? deviceName;

  const ParkActivityEntity({
    required this.id,
    required this.parkId,
    required this.userId,
    this.displayName,
    this.stravaActivityId,
    required this.distanceM,
    required this.movingTimeS,
    required this.elapsedTimeS,
    this.averagePaceSecPerKm,
    this.averageHeartrate,
    this.summaryPolyline,
    required this.startTime,
    this.deviceName,
  });

  @override
  List<Object?> get props => [id, parkId, userId, stravaActivityId, startTime];
}

/// A defined segment within a park (e.g. "Volta do Lago Ibirapuera").
final class ParkSegmentEntity extends Equatable {
  final String id;
  final String parkId;
  final String name;

  /// Ordered points defining the segment path.
  final List<LatLng> path;

  /// Approximate length in meters.
  final double lengthM;

  /// Current record holder.
  final String? recordHolderName;
  final double? recordPaceSecPerKm;

  const ParkSegmentEntity({
    required this.id,
    required this.parkId,
    required this.name,
    required this.path,
    required this.lengthM,
    this.recordHolderName,
    this.recordPaceSecPerKm,
  });

  @override
  List<Object?> get props => [id, parkId, name, path, lengthM];
}
