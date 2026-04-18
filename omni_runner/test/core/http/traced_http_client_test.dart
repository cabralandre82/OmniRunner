import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:omni_runner/core/http/traced_http_client.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// Stub `http.Client` that records every request it sees and returns
/// a canned 200 response. Used to assert which headers TracingClient
/// (wrapped by [TracedHttpClient]) attaches.
class _RecordingClient extends http.BaseClient {
  final List<http.BaseRequest> requests = <http.BaseRequest>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    return http.StreamedResponse(
      Stream<List<int>>.fromIterable(<List<int>>[utf8.encode('{}')]),
      200,
      headers: <String, String>{'content-type': 'application/json'},
    );
  }
}

void main() {
  group('L20-03 — TracedHttpClient', () {
    setUp(() async {
      // Always close before init to wipe any global state from a prior
      // test (Sentry options + propagationContext are process-wide).
      await Sentry.close();
      await Sentry.init((options) {
        options.dsn = '';
        options.tracesSampleRate = 1.0;
      });
    });

    tearDown(() async {
      await Sentry.close();
    });

    test('attaches sentry-trace header to outbound HTTP requests', () async {
      final stub = _RecordingClient();
      final client = TracedHttpClient(inner: stub);

      // Run inside a transaction so a real span is bound to the scope;
      // SentryHttpClient/TracingClient consults the active span when
      // attaching headers. tracePropagationTargets defaults to ['.*'] in
      // tests so any URL is allowed (production sets a real allowlist
      // via main.dart — that wiring is verified separately).
      final tx = Sentry.startTransaction('test-tx', 'test', bindToScope: true);
      try {
        await client.get(Uri.parse('https://test.supabase.co/functions/v1/foo'));
      } finally {
        await tx.finish();
      }

      expect(stub.requests, hasLength(1));
      final headers = stub.requests.first.headers;
      expect(headers.containsKey('sentry-trace'), isTrue,
          reason:
              'TracingClient (via SentryHttpClient) must attach sentry-trace');
    });

    test(
        'currentTraceHeaders() emits sentry-trace from active span context',
        () async {
      final tx = Sentry.startTransaction('test-tx', 'test', bindToScope: true);
      try {
        final headers = TracedHttpClient.currentTraceHeaders();
        expect(headers, isA<Map<String, String>>());
        expect(headers.containsKey('sentry-trace'), isTrue);
        // sentry-trace format: <traceId 32hex>-<spanId 16hex>[-<sampled>]
        final value = headers['sentry-trace']!;
        expect(value, matches(RegExp(r'^[0-9a-f]{32}-[0-9a-f]{16}(-[01])?$')));
      } finally {
        await tx.finish();
      }
    });

    test('currentTraceHeaders() never throws and always returns Map<String, String>',
        () async {
      // Even after Sentry.close(), the helper must NEVER throw and must
      // always return a usable map (callers merge it directly into outbound
      // headers without guards).
      await Sentry.close();

      Map<String, String>? headers;
      expect(
          () => headers = TracedHttpClient.currentTraceHeaders(), returnsNormally);
      expect(headers, isA<Map<String, String>>());
      headers!.forEach((key, value) {
        expect(value, isA<String>());
      });

      // Re-init for tearDown to be able to close again.
      await Sentry.init((options) {
        options.dsn = '';
      });
    });

    test('close() forwards to the inner client', () async {
      var closed = false;
      final stub = _ClosingClient(onClose: () => closed = true);
      final client = TracedHttpClient(inner: stub);
      client.close();
      expect(closed, isTrue);
    });

    test('defaultFirstPartyAllowlist matches expected first-party hosts', () {
      const list = TracedHttpClient.defaultFirstPartyAllowlist;
      bool matchesAny(String url) =>
          list.any((p) => RegExp(p, caseSensitive: false).hasMatch(url));

      // First-party hosts MUST match
      expect(matchesAny('https://abc.supabase.co/rest/v1/users'), isTrue);
      expect(matchesAny('https://omnirunner.app/api/distribute-coins'), isTrue);
      expect(matchesAny('https://staging.omnirunner.app/api/health'), isTrue);
      expect(matchesAny('https://localhost:3000/api/foo'), isTrue);
      expect(matchesAny('https://127.0.0.1:54321/functions/v1/x'), isTrue);

      // Third-party hosts MUST NOT match
      expect(matchesAny('https://www.strava.com/api/v3/uploads'), isFalse,
          reason: 'Strava must not receive trace headers');
      expect(matchesAny('https://api.asaas.com/v3/payments'), isFalse,
          reason: 'Asaas must not receive trace headers');
      expect(matchesAny('https://maps.googleapis.com/maps/api/...'), isFalse,
          reason: 'Google APIs must not receive trace headers');
    });
  });
}

class _ClosingClient extends http.BaseClient {
  _ClosingClient({required this.onClose});
  final void Function() onClose;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return http.StreamedResponse(
      Stream<List<int>>.fromIterable(<List<int>>[<int>[]]),
      200,
    );
  }

  @override
  void close() => onClose();
}
