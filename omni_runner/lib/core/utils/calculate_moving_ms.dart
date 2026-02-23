import 'package:omni_runner/domain/entities/location_point_entity.dart';

/// Estimates total moving time from GPS points.
///
/// Sums time intervals between consecutive points where the gap
/// is below [maxGapMs]. Gaps >= [maxGapMs] are assumed to be pauses
/// (stationary periods where no valid movement was recorded).
///
/// Should be called with **filtered** points (post-FilterLocationPoints)
/// so that GPS jitter during stops has been removed, creating natural
/// gaps in the timestamp sequence.
///
/// Default [maxGapMs] is 30,000 ms (30 seconds).
///
/// Pure function. No state. No side effects.
int calculateMovingMs(
  List<LocationPointEntity> points, {
  int maxGapMs = 30000,
}) {
  if (points.length < 2) return 0;
  var movingMs = 0;
  for (var i = 1; i < points.length; i++) {
    final deltaMs = points[i].timestampMs - points[i - 1].timestampMs;
    if (deltaMs > 0 && deltaMs < maxGapMs) {
      movingMs += deltaMs;
    }
  }
  return movingMs;
}
