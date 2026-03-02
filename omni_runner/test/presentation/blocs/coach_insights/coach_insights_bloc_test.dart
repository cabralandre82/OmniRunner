import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:omni_runner/domain/entities/coach_insight_entity.dart';
import 'package:omni_runner/domain/entities/insight_type_enum.dart';
import 'package:omni_runner/domain/repositories/i_coach_insight_repo.dart';
import 'package:omni_runner/presentation/blocs/coach_insights/coach_insights_bloc.dart';
import 'package:omni_runner/presentation/blocs/coach_insights/coach_insights_event.dart';
import 'package:omni_runner/presentation/blocs/coach_insights/coach_insights_state.dart';

class MockCoachInsightRepo extends Mock implements ICoachInsightRepo {}


Future<List<CoachInsightsState>> _collectStates(
  CoachInsightsBloc bloc, {
  int count = 2,
  Duration timeout = const Duration(seconds: 3),
}) async {
  final states = <CoachInsightsState>[];
  final sub = bloc.stream.listen(states.add);
  final deadline = DateTime.now().add(timeout);
  while (states.length < count && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  await sub.cancel();
  return states;
}

CoachInsightEntity _insight({
  String id = 'i-1',
  String groupId = 'g-1',
  InsightType type = InsightType.performanceDecline,
  bool isRead = false,
  bool dismissed = false,
}) =>
    CoachInsightEntity(
      id: id,
      groupId: groupId,
      type: type,
      priority: InsightPriority.high,
      title: 'Insight $id',
      message: 'Details for $id',
      createdAtMs: 1000000,
      readAtMs: isRead ? 1000001 : null,
      dismissed: dismissed,
    );

void main() {
  late MockCoachInsightRepo repo;

  setUpAll(() {
    registerFallbackValue(_insight());
  });

  setUp(() {
    repo = MockCoachInsightRepo();
  });

  group('CoachInsightsBloc', () {
    test('initial state is CoachInsightsInitial', () {
      final bloc = CoachInsightsBloc(repo: repo);
      expect(bloc.state, isA<CoachInsightsInitial>());
      bloc.close();
    });

    test('LoadCoachInsights emits Loading then Loaded', () async {
      final insights = [_insight(), _insight(id: 'i-2')];
      when(() => repo.getByGroupId('g-1')).thenAnswer((_) async => insights);
      when(() => repo.countUnreadByGroupId('g-1')).thenAnswer((_) async => 2);

      final bloc = CoachInsightsBloc(repo: repo);
      bloc.add(const LoadCoachInsights(groupId: 'g-1'));
      final states = await _collectStates(bloc);

      expect(states[0], isA<CoachInsightsLoading>());
      expect(states[1], isA<CoachInsightsLoaded>());
      final loaded = states[1] as CoachInsightsLoaded;
      expect(loaded.insights.length, 2);
      expect(loaded.unreadCount, 2);

      await bloc.close();
    });

    test('LoadCoachInsights emits Empty when all dismissed', () async {
      final insights = [_insight(dismissed: true)];
      when(() => repo.getByGroupId('g-1')).thenAnswer((_) async => insights);
      when(() => repo.countUnreadByGroupId('g-1')).thenAnswer((_) async => 0);

      final bloc = CoachInsightsBloc(repo: repo);
      bloc.add(const LoadCoachInsights(groupId: 'g-1'));
      final states = await _collectStates(bloc);

      expect(states[1], isA<CoachInsightsEmpty>());
      await bloc.close();
    });

    test('LoadCoachInsights emits Error on exception', () async {
      when(() => repo.getByGroupId('g-1'))
          .thenThrow(Exception('network failure'));

      final bloc = CoachInsightsBloc(repo: repo);
      bloc.add(const LoadCoachInsights(groupId: 'g-1'));
      final states = await _collectStates(bloc);

      expect(states[1], isA<CoachInsightsError>());
      expect((states[1] as CoachInsightsError).message,
          contains('network failure'));
      await bloc.close();
    });

    test('FilterByType uses getByGroupAndType', () async {
      final insights = [
        _insight(type: InsightType.inactivityWarning),
      ];
      when(() => repo.getByGroupId('g-1'))
          .thenAnswer((_) async => [_insight()]);
      when(() => repo.countUnreadByGroupId('g-1')).thenAnswer((_) async => 1);
      when(() => repo.getByGroupAndType(
              groupId: 'g-1', type: InsightType.inactivityWarning))
          .thenAnswer((_) async => insights);

      final bloc = CoachInsightsBloc(repo: repo);
      bloc.add(const LoadCoachInsights(groupId: 'g-1'));
      await _collectStates(bloc);

      bloc.add(const FilterByType(InsightType.inactivityWarning));
      final states2 = await _collectStates(bloc);

      expect(states2[1], isA<CoachInsightsLoaded>());
      final loaded = states2[1] as CoachInsightsLoaded;
      expect(loaded.typeFilter, InsightType.inactivityWarning);
      expect(loaded.insights.first.type, InsightType.inactivityWarning);

      verify(() => repo.getByGroupAndType(
          groupId: 'g-1', type: InsightType.inactivityWarning)).called(1);
      await bloc.close();
    });

    test('FilterUnreadOnly filters out read insights', () async {
      final insights = [
        _insight(id: 'i-1', isRead: false),
        _insight(id: 'i-2', isRead: true),
      ];
      when(() => repo.getByGroupId('g-1')).thenAnswer((_) async => insights);
      when(() => repo.countUnreadByGroupId('g-1')).thenAnswer((_) async => 1);

      final bloc = CoachInsightsBloc(repo: repo);
      bloc.add(const LoadCoachInsights(groupId: 'g-1'));
      await _collectStates(bloc);

      bloc.add(const FilterUnreadOnly(true));
      final states = await _collectStates(bloc);

      expect(states[1], isA<CoachInsightsLoaded>());
      final loaded = states[1] as CoachInsightsLoaded;
      expect(loaded.insights.length, 1);
      expect(loaded.unreadOnly, true);
      await bloc.close();
    });

    test('MarkInsightRead calls repo.update', () async {
      final insight = _insight(id: 'i-1');
      when(() => repo.getById('i-1')).thenAnswer((_) async => insight);
      when(() => repo.update(any())).thenAnswer((_) async {});
      when(() => repo.getByGroupId('g-1'))
          .thenAnswer((_) async => [insight.markRead(2000000)]);
      when(() => repo.countUnreadByGroupId('g-1')).thenAnswer((_) async => 0);

      final bloc = CoachInsightsBloc(repo: repo);
      bloc.add(const LoadCoachInsights(groupId: 'g-1'));
      await _collectStates(bloc);

      bloc.add(const MarkInsightRead('i-1'));
      final states = await _collectStates(bloc);

      verify(() => repo.update(any())).called(1);
      expect(states[1], isA<CoachInsightsLoaded>());
      await bloc.close();
    });

    test('DismissInsight calls repo.update and refreshes', () async {
      final insight = _insight(id: 'i-1');
      when(() => repo.getById('i-1')).thenAnswer((_) async => insight);
      when(() => repo.update(any())).thenAnswer((_) async {});
      when(() => repo.getByGroupId('g-1')).thenAnswer((_) async => []);
      when(() => repo.countUnreadByGroupId('g-1')).thenAnswer((_) async => 0);

      final bloc = CoachInsightsBloc(repo: repo);
      bloc.add(const LoadCoachInsights(groupId: 'g-1'));
      await _collectStates(bloc);

      bloc.add(const DismissInsight('i-1'));
      final states = await _collectStates(bloc);

      verify(() => repo.update(any())).called(1);
      expect(states[1], isA<CoachInsightsEmpty>());
      await bloc.close();
    });

    test('RefreshCoachInsights does nothing if groupId not set', () async {
      final bloc = CoachInsightsBloc(repo: repo);
      bloc.add(const RefreshCoachInsights());

      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(bloc.state, isA<CoachInsightsInitial>());
      await bloc.close();
    });
  });
}
