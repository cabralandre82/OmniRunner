import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:omni_runner/core/service_locator.dart';
import 'package:omni_runner/domain/entities/location_point_entity.dart';
import 'package:omni_runner/presentation/screens/run_summary_screen.dart';

import '../../helpers/pump_app.dart';
import '../../helpers/test_di.dart';

final _points = [
  const LocationPointEntity(lat: -23.55, lng: -46.63, timestampMs: 1000),
  const LocationPointEntity(lat: -23.551, lng: -46.631, timestampMs: 2000),
  const LocationPointEntity(lat: -23.552, lng: -46.632, timestampMs: 3000),
];

/// FunctionsClient that returns a specific AI comment.
class _CommentFunctionsClient extends Fake implements FunctionsClient {
  final String? comment;
  _CommentFunctionsClient({this.comment});

  @override
  Future<FunctionResponse> invoke(
    String functionName, {
    Map<String, String>? headers,
    Object? body,
    Iterable<dynamic>? files,
    Map<String, dynamic>? queryParameters,
    HttpMethod method = HttpMethod.post,
    String? region,
  }) async {
    if (functionName == 'generate-run-comment') {
      return FunctionResponse(
        status: 200,
        data: <String, dynamic>{'comment': comment},
      );
    }
    return FunctionResponse(status: 200, data: <String, dynamic>{});
  }
}

/// SupabaseClient that uses a custom FunctionsClient.
class _SupabaseWithFunctions extends FakeSupabaseClient {
  final FunctionsClient _functions;
  _SupabaseWithFunctions(this._functions);

  @override
  FunctionsClient get functions => _functions;
}

void _registerSupabaseWithFunctions(FunctionsClient functionsClient) {
  if (sl.isRegistered<SupabaseClient>()) sl.unregister<SupabaseClient>();
  sl.registerLazySingleton<SupabaseClient>(
    () => _SupabaseWithFunctions(functionsClient),
  );
}

void main() {
  group('RunSummaryScreen', () {
    final origOnError = FlutterError.onError;

    void silenceNoisyErrors() {
      FlutterError.onError = (details) {
        final msg = details.exceptionAsString();
        if (msg.contains('overflowed')) return;
        if (msg.contains('MissingPluginException')) return;
        if (msg.contains('PlatformException')) return;
        origOnError?.call(details);
      };
    }

    void mockMapChannel() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/maplibre_gl'),
        (call) async => null,
      );
    }

    void clearMapChannel() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/maplibre_gl'),
        null,
      );
    }

    setUp(() {
      ensureSupabaseClientRegistered();
      silenceNoisyErrors();
      mockMapChannel();
    });

    tearDown(() {
      FlutterError.onError = origOnError;
      clearMapChannel();
    });

    testWidgets('renders without crash', (tester) async {
      await tester.pumpApp(
        RunSummaryScreen(
          points: _points,
          totalDistanceM: 5000,
          elapsedMs: 1800000,
          avgPaceSecPerKm: 360,
        ),
        wrapScaffold: false,
      );

      expect(find.byType(RunSummaryScreen), findsOneWidget);
      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('shows title text', (tester) async {
      await tester.pumpApp(
        RunSummaryScreen(
          points: _points,
          totalDistanceM: 5000,
          elapsedMs: 1800000,
        ),
        wrapScaffold: false,
      );

      expect(find.text('Resumo da Corrida'), findsOneWidget);
    });

    testWidgets('shows close button', (tester) async {
      await tester.pumpApp(
        RunSummaryScreen(
          points: _points,
          totalDistanceM: 5000,
          elapsedMs: 1800000,
        ),
        wrapScaffold: false,
      );

      expect(find.byIcon(Icons.close), findsOneWidget);
    });

    testWidgets(
        'AI comment card not visible when functions client returns null comment',
        (tester) async {
      // Default FakeSupabaseClient returns {} → comment is null → no card
      await tester.pumpApp(
        RunSummaryScreen(
          points: _points,
          totalDistanceM: 5000,
          elapsedMs: 1800000,
        ),
        wrapScaffold: false,
      );

      // Flush async _fetchAiComment
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('✨'), findsNothing);
    });

    testWidgets('AI comment card appears when functions returns a comment',
        (tester) async {
      const commentText = 'Boa corrida! Seu pace foi 3% melhor que sua média.';
      _registerSupabaseWithFunctions(
        _CommentFunctionsClient(comment: commentText),
      );

      await tester.pumpApp(
        RunSummaryScreen(
          points: _points,
          totalDistanceM: 5000,
          elapsedMs: 1800000,
          avgPaceSecPerKm: 360,
        ),
        wrapScaffold: false,
      );

      // Wait for async AI call to complete
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text(commentText), findsOneWidget);
    });

    testWidgets('AI loading shimmer appears before comment resolves',
        (tester) async {
      // Use the default no-op client — the loading shimmer shows synchronously
      // before the async future completes. Checking it right after the initial
      // pump (before tester.pump advances async work) confirms the behaviour.
      ensureSupabaseClientRegistered();

      await tester.pumpApp(
        RunSummaryScreen(
          points: _points,
          totalDistanceM: 5000,
          elapsedMs: 1800000,
        ),
        wrapScaffold: false,
        skipInitialPump: true, // do not auto-pump so we catch the loading state
      );

      // Immediately after rendering, before async work completes, shimmer shows
      expect(find.text('Analisando sua corrida...'), findsOneWidget);

      // Flush all pending timers/futures to clean up
      await tester.pump(const Duration(milliseconds: 500));
    });

    testWidgets('AI card not shown if functions throws an exception',
        (tester) async {
      _registerSupabaseWithFunctions(_ThrowingFunctionsClient());

      await tester.pumpApp(
        RunSummaryScreen(
          points: _points,
          totalDistanceM: 5000,
          elapsedMs: 1800000,
        ),
        wrapScaffold: false,
      );

      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Analisando sua corrida...'), findsNothing);
      expect(find.text('✨'), findsNothing);
    });
  });
}

/// FunctionsClient that always throws.
class _ThrowingFunctionsClient extends Fake implements FunctionsClient {
  @override
  Future<FunctionResponse> invoke(
    String functionName, {
    Map<String, String>? headers,
    Object? body,
    Iterable<dynamic>? files,
    Map<String, dynamic>? queryParameters,
    HttpMethod method = HttpMethod.post,
    String? region,
  }) async {
    throw Exception('Network error');
  }
}
