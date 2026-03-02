import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:omni_runner/domain/entities/feed_item_entity.dart';
import 'package:omni_runner/domain/repositories/i_feed_remote_source.dart';
import 'package:omni_runner/presentation/blocs/assessoria_feed/assessoria_feed_bloc.dart';
import 'package:omni_runner/presentation/blocs/assessoria_feed/assessoria_feed_event.dart';
import 'package:omni_runner/presentation/blocs/assessoria_feed/assessoria_feed_state.dart';

// ---------------------------------------------------------------------------
// Fake
// ---------------------------------------------------------------------------

class _FakeRemote implements IFeedRemoteSource {
  List<FeedItemEntity> result = [];
  Exception? error;
  int callCount = 0;

  @override
  Future<List<FeedItemEntity>> fetchFeed({
    required String groupId,
    required int limit,
    int? beforeMs,
  }) async {
    callCount++;
    if (error != null) throw error!;
    return result;
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const _groupId = 'group-1';

FeedItemEntity _item(String id, {int createdAtMs = 1000000}) =>
    FeedItemEntity(
      id: id,
      actorUserId: 'u-1',
      actorName: 'Alice',
      eventType: FeedEventType.sessionCompleted,
      payload: const {},
      createdAtMs: createdAtMs,
    );

Future<List<AssessoriaFeedState>> _collectStates(
  AssessoriaFeedBloc bloc, {
  required int count,
  Duration timeout = const Duration(seconds: 5),
}) async {
  final states = <AssessoriaFeedState>[];
  final completer = Completer<void>();
  final sub = bloc.stream.listen((s) {
    states.add(s);
    if (states.length >= count && !completer.isCompleted) {
      completer.complete();
    }
  });
  await completer.future.timeout(timeout, onTimeout: () {});
  await sub.cancel();
  return states;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late _FakeRemote remote;

  setUp(() {
    remote = _FakeRemote();
  });

  group('AssessoriaFeedBloc', () {
    test('initial state is FeedInitial', () {
      final bloc = AssessoriaFeedBloc(remote: remote);
      expect(bloc.state, isA<FeedInitial>());
      bloc.close();
    });

    test('emits [Loading, Loaded] when feed has items', () async {
      remote.result = [_item('f1'), _item('f2')];
      final bloc = AssessoriaFeedBloc(remote: remote);

      final future = _collectStates(bloc, count: 2);
      bloc.add(const LoadFeed(_groupId));
      final states = await future;
      await bloc.close();

      expect(states[0], isA<FeedLoading>());
      expect(states[1], isA<FeedLoaded>());
      expect((states[1] as FeedLoaded).items, hasLength(2));
    });

    test('emits [Loading, FeedEmpty] when no items', () async {
      remote.result = [];
      final bloc = AssessoriaFeedBloc(remote: remote);

      final future = _collectStates(bloc, count: 2);
      bloc.add(const LoadFeed(_groupId));
      final states = await future;
      await bloc.close();

      expect(states[1], isA<FeedEmpty>());
    });

    test('emits [Loading, Error] on exception', () async {
      remote.error = Exception('offline');
      final bloc = AssessoriaFeedBloc(remote: remote);

      final future = _collectStates(bloc, count: 2);
      bloc.add(const LoadFeed(_groupId));
      final states = await future;
      await bloc.close();

      expect(states[1], isA<FeedError>());
      expect((states[1] as FeedError).message, contains('feed'));
    });

    test('RefreshFeed reloads items', () async {
      remote.result = [_item('f1')];
      final bloc = AssessoriaFeedBloc(remote: remote);

      // Initial load
      var future = _collectStates(bloc, count: 2);
      bloc.add(const LoadFeed(_groupId));
      await future;

      // Refresh with new data
      remote.result = [_item('f1'), _item('f2')];
      future = _collectStates(bloc, count: 1);
      bloc.add(const RefreshFeed());
      final states = await future;
      await bloc.close();

      expect(states[0], isA<FeedLoaded>());
      expect((states[0] as FeedLoaded).items, hasLength(2));
      expect(remote.callCount, 2);
    });
  });
}
