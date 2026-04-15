import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:omni_runner/core/offline/offline_queue.dart';
import 'package:omni_runner/core/storage/preferences_keys.dart';

/// Unused when [rpcInvoker] is provided; satisfies [OfflineQueue] constructor.
class _UnusedClient extends Fake implements SupabaseClient {}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('OfflineQueue', () {
    test('enqueue then replay clears queue on success', () async {
      final prefs = await SharedPreferences.getInstance();
      final calls = <String>[];
      final queue = OfflineQueue(
        prefs: prefs,
        client: _UnusedClient(),
        rpcInvoker: (op, params) async {
          calls.add('$op:${params['x']}');
        },
      );

      await queue.enqueue('fn_test', {'x': 1});
      expect(await queue.length, 1);

      final n = await queue.replay();
      expect(n, 1);
      expect(await queue.length, 0);
      expect(calls, ['fn_test:1']);
    });

    test('replay drops item after max retries on persistent failure', () async {
      final prefs = await SharedPreferences.getInstance();
      var attempts = 0;
      final queue = OfflineQueue(
        prefs: prefs,
        client: _UnusedClient(),
        rpcInvoker: (op, params) async {
          attempts++;
          throw Exception('network');
        },
      );

      await queue.enqueue('fn_fail', {});
      expect(await queue.length, 1);

      await queue.replay();
      expect(await queue.length, 1);
      await queue.replay();
      expect(await queue.length, 1);
      await queue.replay();
      expect(await queue.length, 0);

      expect(attempts, 3);
    });

    test('skips malformed JSON entries when loading', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(PreferencesKeys.offlineQueueItems, [
        'not-json',
        '{"id":"1","operation":"fn_ok","params":{},"timestamp":"2099-01-01T00:00:00.000Z","retryCount":0}',
      ]);

      var invoked = false;
      final queue = OfflineQueue(
        prefs: prefs,
        client: _UnusedClient(),
        rpcInvoker: (op, params) async {
          expect(op, 'fn_ok');
          invoked = true;
        },
      );

      final n = await queue.replay();
      expect(n, 1);
      expect(invoked, isTrue);
    });
  });
}
