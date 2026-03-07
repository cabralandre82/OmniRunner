import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/group_entity.dart';
import 'package:omni_runner/presentation/blocs/groups/groups_bloc.dart';
import 'package:omni_runner/presentation/blocs/groups/groups_state.dart';
import 'package:omni_runner/presentation/screens/groups_screen.dart';

import '../../helpers/pump_app.dart';

class _FakeGroupsBloc extends Cubit<GroupsState> implements GroupsBloc {
  _FakeGroupsBloc(super.initial);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _group1 = GroupEntity(
  id: 'g1',
  name: 'Corredores do Parque',
  description: 'Grupo de corrida no Ibirapuera',
  createdByUserId: 'u1',
  createdAtMs: DateTime(2026, 1, 1).millisecondsSinceEpoch,
  privacy: GroupPrivacy.open,
  memberCount: 12,
  maxMembers: 50,
);

final _group2 = GroupEntity(
  id: 'g2',
  name: 'Equipe Elite',
  description: 'Treinamento avançado',
  createdByUserId: 'u2',
  createdAtMs: DateTime(2026, 2, 1).millisecondsSinceEpoch,
  privacy: GroupPrivacy.closed,
  memberCount: 8,
  maxMembers: 20,
);

void main() {
  group('GroupsScreen', () {
    final origOnError = FlutterError.onError;
    setUp(() {
      FlutterError.onError = (details) {
        final msg = details.exceptionAsString();
        if (msg.contains('overflowed')) return;
        origOnError?.call(details);
      };
    });
    tearDown(() => FlutterError.onError = origOnError);

    testWidgets('shows loading indicator for GroupsLoading state',
        (tester) async {
      final bloc = _FakeGroupsBloc(const GroupsLoading());

      await tester.pumpApp(
        BlocProvider<GroupsBloc>.value(
          value: bloc,
          child: const GroupsScreen(),
        ),
        wrapScaffold: false,
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows initial message for GroupsInitial state',
        (tester) async {
      final bloc = _FakeGroupsBloc(const GroupsInitial());

      await tester.pumpApp(
        BlocProvider<GroupsBloc>.value(
          value: bloc,
          child: const GroupsScreen(),
        ),
        wrapScaffold: false,
      );

      expect(find.text('Carregue seus grupos.'), findsOneWidget);
    });

    testWidgets('shows error message for GroupsError state', (tester) async {
      final bloc =
          _FakeGroupsBloc(const GroupsError('Erro ao carregar grupos'));

      await tester.pumpApp(
        BlocProvider<GroupsBloc>.value(
          value: bloc,
          child: const GroupsScreen(),
        ),
        wrapScaffold: false,
      );

      expect(find.text('Erro ao carregar grupos'), findsOneWidget);
    });

    testWidgets('shows empty state when no groups', (tester) async {
      final bloc = _FakeGroupsBloc(const GroupsLoaded(groups: []));

      await tester.pumpApp(
        BlocProvider<GroupsBloc>.value(
          value: bloc,
          child: const GroupsScreen(),
        ),
        wrapScaffold: false,
      );

      expect(find.text('Nenhum grupo'), findsOneWidget);
      expect(find.byIcon(Icons.group_outlined), findsOneWidget);
    });

    testWidgets('shows loaded groups', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final bloc =
          _FakeGroupsBloc(GroupsLoaded(groups: [_group1, _group2]));

      await tester.pumpApp(
        BlocProvider<GroupsBloc>.value(
          value: bloc,
          child: const GroupsScreen(),
        ),
        wrapScaffold: false,
      );

      expect(find.text('Corredores do Parque'), findsOneWidget);
      expect(find.text('Equipe Elite'), findsOneWidget);
    });

    testWidgets('shows privacy labels in group cards', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final bloc =
          _FakeGroupsBloc(GroupsLoaded(groups: [_group1, _group2]));

      await tester.pumpApp(
        BlocProvider<GroupsBloc>.value(
          value: bloc,
          child: const GroupsScreen(),
        ),
        wrapScaffold: false,
      );

      expect(find.text('Aberto'), findsOneWidget);
      expect(find.text('Fechado'), findsOneWidget);
    });

    testWidgets('shows member count in group cards', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final bloc = _FakeGroupsBloc(GroupsLoaded(groups: [_group1]));

      await tester.pumpApp(
        BlocProvider<GroupsBloc>.value(
          value: bloc,
          child: const GroupsScreen(),
        ),
        wrapScaffold: false,
      );

      expect(find.text('12/50'), findsOneWidget);
    });

    testWidgets('has refresh button in app bar', (tester) async {
      final bloc = _FakeGroupsBloc(const GroupsInitial());

      await tester.pumpApp(
        BlocProvider<GroupsBloc>.value(
          value: bloc,
          child: const GroupsScreen(),
        ),
        wrapScaffold: false,
      );

      expect(find.byIcon(Icons.refresh), findsOneWidget);
    });

    testWidgets('renders app bar', (tester) async {
      final bloc = _FakeGroupsBloc(const GroupsInitial());

      await tester.pumpApp(
        BlocProvider<GroupsBloc>.value(
          value: bloc,
          child: const GroupsScreen(),
        ),
        wrapScaffold: false,
      );

      expect(find.byType(AppBar), findsOneWidget);
    });
  });
}
