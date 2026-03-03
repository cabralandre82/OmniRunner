/// Client-side sliding-window rate limiter.
///
/// Tracks call timestamps and rejects new calls when [maxCalls]
/// have been made within the rolling [window].
class RateLimiter {
  final Duration window;
  final int maxCalls;
  final List<DateTime> _timestamps = [];

  RateLimiter({this.window = const Duration(minutes: 1), this.maxCalls = 30});

  bool canProceed() {
    final now = DateTime.now();
    _timestamps.removeWhere((t) => now.difference(t) > window);
    if (_timestamps.length >= maxCalls) return false;
    _timestamps.add(now);
    return true;
  }

  void reset() => _timestamps.clear();
}
