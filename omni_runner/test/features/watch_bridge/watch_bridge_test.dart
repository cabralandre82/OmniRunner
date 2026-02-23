import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/features/watch_bridge/watch_bridge.dart';
import 'package:omni_runner/features/watch_bridge/watch_session_payload.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MethodChannel channel;
  late WatchBridge bridge;

  setUp(() {
    channel = const MethodChannel('omnirunner/watch');
    bridge = WatchBridge(channel: channel);
    bridge.init();
  });

  tearDown(() {
    bridge.dispose();
  });

  Map<String, dynamic> validSessionMap() => {
        'version': 1,
        'source': 'wear_os',
        'sessionId': 'test-session-1',
        'startMs': 1000000,
        'endMs': 1060000,
        'totalDistanceM': 3000.0,
        'movingMs': 55000,
        'avgBpm': 150,
        'maxBpm': 180,
        'isVerified': true,
        'integrityFlags': <String>[],
        'points': [
          {
            'lat': -23.55,
            'lng': -46.63,
            'alt': 750.0,
            'accuracy': 4.0,
            'speed': 3.2,
            'timestampMs': 1000001,
          },
        ],
        'hrSamples': [
          {'bpm': 150, 'timestampMs': 1000001},
        ],
      };

  group('WatchBridge — onSessionReceived', () {
    test('emits parsed WatchSessionPayload', () async {
      WatchSessionPayload? received;

      bridge.onSessionReceived.listen((payload) {
        received = payload;
      });

      // Simulate native call
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
        'omnirunner/watch',
        const StandardMethodCodec().encodeMethodCall(
          MethodCall('onSessionReceived', validSessionMap()),
        ),
        (_) {},
      );

      await Future<void>.delayed(Duration.zero);

      expect(received, isNotNull);
      expect(received!.sessionId, 'test-session-1');
      expect(received!.source, 'wear_os');
      expect(received!.points, hasLength(1));
      expect(received!.hrSamples, hasLength(1));
    });

    test('ignores invalid payload without error', () async {
      WatchSessionPayload? received;

      bridge.onSessionReceived.listen((payload) {
        received = payload;
      });

      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
        'omnirunner/watch',
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('onSessionReceived', <String, dynamic>{}),
        ),
        (_) {},
      );

      await Future<void>.delayed(Duration.zero);

      expect(received, isNull);
    });
  });

  group('WatchBridge — onLiveSample', () {
    test('emits parsed WatchLiveSample', () async {
      WatchLiveSample? received;

      bridge.onLiveSample.listen((sample) {
        received = sample;
      });

      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
        'omnirunner/watch',
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('onLiveSample', {
            'sessionId': 'live-1',
            'bpm': 155,
            'pace': 320.0,
            'distanceM': 2500.0,
            'elapsedS': 600,
            'timestampMs': 1700000000,
          }),
        ),
        (_) {},
      );

      await Future<void>.delayed(Duration.zero);

      expect(received, isNotNull);
      expect(received!.sessionId, 'live-1');
      expect(received!.bpm, 155);
      expect(received!.distanceM, 2500.0);
    });
  });

  group('WatchBridge — onWatchStateChanged', () {
    test('emits parsed WatchWorkoutState', () async {
      WatchWorkoutState? received;

      bridge.onWatchStateChanged.listen((state) {
        received = state;
      });

      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
        'omnirunner/watch',
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('onWatchStateChanged', {
            'sessionId': 'sess-1',
            'state': 'paused',
            'timestampMs': 1700000000,
          }),
        ),
        (_) {},
      );

      await Future<void>.delayed(Duration.zero);

      expect(received, isNotNull);
      expect(received!.sessionId, 'sess-1');
      expect(received!.isPaused, true);
    });
  });

  group('WatchBridge — onReachabilityChanged', () {
    test('emits reachability boolean', () async {
      bool? received;

      bridge.onReachabilityChanged.listen((v) {
        received = v;
      });

      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
        'omnirunner/watch',
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('onReachabilityChanged', {'isReachable': true}),
        ),
        (_) {},
      );

      await Future<void>.delayed(Duration.zero);

      expect(received, true);
    });
  });

  group('WatchBridge — Dart → Native', () {
    test('acknowledgeSession calls native method', () async {
      final calls = <MethodCall>[];

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return null;
      });

      await bridge.acknowledgeSession('ack-session-1');

      expect(calls, hasLength(1));
      expect(calls.first.method, 'acknowledgeSession');
      expect(calls.first.arguments, {'sessionId': 'ack-session-1'});

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('getWatchStatus returns status map', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'getWatchStatus') {
          return {
            'isSupported': true,
            'isReachable': true,
            'isPaired': true,
          };
        }
        return null;
      });

      final status = await bridge.getWatchStatus();

      expect(status['isSupported'], true);
      expect(status['isReachable'], true);
      expect(status['isPaired'], true);

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('getWatchStatus handles PlatformException gracefully', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'ERROR', message: 'No watch');
      });

      final status = await bridge.getWatchStatus();

      expect(status['error'], 'No watch');

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
  });
}
