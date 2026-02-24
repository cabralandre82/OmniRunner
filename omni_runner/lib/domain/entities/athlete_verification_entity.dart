import 'package:equatable/equatable.dart';

enum VerificationStatus {
  unverified,
  calibrating,
  monitored,
  verified,
  downgraded,
}

/// Read-only snapshot of the athlete's verification state + checklist.
///
/// Populated from the server RPC `get_verification_state()`.
/// The app displays this; the server decides eligibility.
final class AthleteVerificationEntity extends Equatable {
  final VerificationStatus status;
  final int trustScore;
  final DateTime? verifiedAt;
  final DateTime? lastEvalAt;
  final List<String> verificationFlags;
  final int calibrationValidRuns;

  // Checklist booleans (null = not evaluated / future feature)
  final bool? identityOk;
  final bool? permissionsOk;
  final bool validRunsOk;
  final bool integrityOk;
  final bool baselineOk;
  final bool trustOk;

  // Raw counts for progress display
  final int validRunsCount;
  final int flaggedRunsRecent;
  final double totalDistanceM;
  final double avgDistanceM;

  // Thresholds from server (single source of truth)
  final int requiredValidRuns;
  final int requiredTrustScore;

  const AthleteVerificationEntity({
    required this.status,
    required this.trustScore,
    this.verifiedAt,
    this.lastEvalAt,
    this.verificationFlags = const [],
    this.calibrationValidRuns = 0,
    this.identityOk,
    this.permissionsOk,
    required this.validRunsOk,
    required this.integrityOk,
    required this.baselineOk,
    required this.trustOk,
    required this.validRunsCount,
    this.flaggedRunsRecent = 0,
    this.totalDistanceM = 0,
    this.avgDistanceM = 0,
    this.requiredValidRuns = 7,
    this.requiredTrustScore = 80,
  });

  bool get isVerified => status == VerificationStatus.verified;

  /// How many checklist items (excluding null/future) are complete.
  int get completedChecks {
    int count = 0;
    if (validRunsOk) count++;
    if (integrityOk) count++;
    if (baselineOk) count++;
    if (trustOk) count++;
    return count;
  }

  int get totalChecks => 4;

  double get progress => totalChecks > 0 ? completedChecks / totalChecks : 0;

  @override
  List<Object?> get props => [
        status,
        trustScore,
        verifiedAt,
        lastEvalAt,
        verificationFlags,
        calibrationValidRuns,
        identityOk,
        permissionsOk,
        validRunsOk,
        integrityOk,
        baselineOk,
        trustOk,
        validRunsCount,
        flaggedRunsRecent,
        totalDistanceM,
        avgDistanceM,
        requiredValidRuns,
        requiredTrustScore,
      ];

  static VerificationStatus parseStatus(String? s) => switch (s) {
        'CALIBRATING' => VerificationStatus.calibrating,
        'MONITORED' => VerificationStatus.monitored,
        'VERIFIED' => VerificationStatus.verified,
        'DOWNGRADED' => VerificationStatus.downgraded,
        _ => VerificationStatus.unverified,
      };
}
