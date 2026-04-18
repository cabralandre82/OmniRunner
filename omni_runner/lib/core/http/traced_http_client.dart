/// L20-03 — Distributed-tracing HTTP wrapper for the mobile app.
///
/// Wraps Sentry's `SentryHttpClient` (which composes `TracingClient` +
/// `BreadcrumbClient` + `FailedRequestClient`) so every outbound request
/// to allowlisted hosts (Portal API, Supabase Edge Functions) carries
/// `sentry-trace` + `baggage` (and optionally W3C `traceparent`) headers.
///
/// The receiving service (Portal Next.js) joins the same trace, so a
/// single trace tree spans mobile → portal → DB → webhook.
///
/// Usage (preferred for first-party calls):
/// ```dart
/// final client = TracedHttpClient();
/// final res = await client.get(Uri.parse('$portalUrl/api/distribute-coins'));
/// ```
///
/// For `SupabaseClient.functions.invoke(...)` use the static helper:
/// ```dart
/// final headers = TracedHttpClient.currentTraceHeaders();
/// await db.functions.invoke('champ-create', body: {...}, headers: headers);
/// ```
///
/// IMPORTANT — third-party services (Strava, Asaas, etc.) MUST NOT receive
/// our trace headers. The `tracePropagationTargets` allowlist is set in
/// `main.dart` at `SentryFlutter.init` time (see also that file).
library;

// L20-03 — `sentry_flutter` is the public Flutter wrapper around `sentry`
// (which is the pure-Dart core). It re-exports everything we need
// (HubAdapter, SentryHttpClient, addTracingHeadersToHttpHeader). We
// intentionally depend on the wrapper, not `sentry` directly, to track
// the Flutter SDK lifecycle (init lives in main.dart via SentryFlutter).
import 'package:http/http.dart' as http;
import 'package:sentry_flutter/sentry_flutter.dart';

class TracedHttpClient extends http.BaseClient {
  /// Build a client. Trace headers are auto-attached only to URLs matching
  /// `tracePropagationTargets` (configured in `main.dart` at Sentry init).
  factory TracedHttpClient({http.Client? inner}) {
    return TracedHttpClient._(SentryHttpClient(client: inner ?? http.Client()));
  }

  TracedHttpClient._(this._inner);

  final http.Client _inner;

  /// Default first-party allowlist for `tracePropagationTargets`.
  ///
  /// Callers (typically `main.dart`) should pass these to `Sentry.init`'s
  /// `options.tracePropagationTargets` so trace headers leak ONLY to
  /// allowlisted hosts. Third parties (Strava, Asaas, Google APIs) MUST
  /// be excluded — leaking trace context to them is a data-hygiene issue
  /// and they ignore it anyway.
  static const List<String> defaultFirstPartyAllowlist = <String>[
    r'.*\.supabase\.co',
    r'omnirunner\.app',
    r'.*\.omnirunner\.app',
    r'omnirunner\.com\.br',
    r'.*\.omnirunner\.com\.br',
    r'^https?://localhost',
    r'^https?://127\.0\.0\.1',
  ];

  /// Compute trace headers for the active span (or scope-level propagation
  /// context, if no span). Returns a Map<String, String> safe to merge
  /// into any header bag.
  ///
  /// Use this for code paths that don't go through `http.Client` —
  /// notably `SupabaseClient.functions.invoke(headers: ...)` and the
  /// Supabase Realtime channel auth header.
  ///
  /// Falls back to the scope's `propagationContext` (which Sentry seeds
  /// at every request boundary even when no span is active) so we always
  /// emit a trace_id; downstream services can still join the trace.
  ///
  /// Never throws. Returns an empty map on any error (Sentry not init,
  /// etc) so callers can always merge it without guards.
  static Map<String, String> currentTraceHeaders() {
    try {
      final hub = HubAdapter();
      final headers = <String, dynamic>{};
      // ignore: invalid_use_of_internal_member
      addTracingHeadersToHttpHeader(headers, hub);
      return headers.map((key, value) => MapEntry(key, value.toString()));
    } on Object {
      return const <String, String>{};
    }
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      _inner.send(request);

  @override
  void close() => _inner.close();
}
