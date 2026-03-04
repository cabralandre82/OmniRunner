/// Configurable TTL (time-to-live) for Isar cache staleness.
///
/// When cached data is older than [defaultTtlMs], it should be refetched
/// from the backend. Values in milliseconds.
class CacheTtlConfig {
  CacheTtlConfig._();

  /// Default TTL: 5 minutes. Cached data older than this is considered stale.
  static const int defaultTtlMs = 5 * 60 * 1000;

  /// Shorter TTL for financial data (wallet, ledger): 2 minutes.
  static const int financialTtlMs = 2 * 60 * 1000;

  /// Longer TTL for relatively static data (coaching groups): 15 minutes.
  static const int coachingTtlMs = 15 * 60 * 1000;
}
