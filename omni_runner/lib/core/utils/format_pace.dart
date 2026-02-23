/// Formats a pace value from seconds per kilometer to `mm:ss/km`.
///
/// Returns `'--:--/km'` for null, NaN, infinity, zero, or negative values.
///
/// The value is rounded to the nearest whole second before formatting,
/// which correctly handles the 59.5→60 rollover into the next minute.
///
/// Examples:
/// - `300.0` → `'05:00/km'`
/// - `270.0` → `'04:30/km'`
/// - `null`  → `'--:--/km'`
///
/// Pure function. No state. No side effects.
String formatPace(double? secPerKm) {
  if (secPerKm == null ||
      secPerKm.isNaN ||
      secPerKm.isInfinite ||
      secPerKm <= 0) {
    return '--:--/km';
  }

  final totalSeconds = secPerKm.round();
  if (totalSeconds <= 0) return '--:--/km';

  final min = totalSeconds ~/ 60;
  final sec = totalSeconds % 60;

  final mm = min.toString().padLeft(2, '0');
  final ss = sec.toString().padLeft(2, '0');

  return '$mm:$ss/km';
}
