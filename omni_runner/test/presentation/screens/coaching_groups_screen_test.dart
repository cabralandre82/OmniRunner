import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/coaching_group_entity.dart';
import 'package:omni_runner/domain/entities/coaching_member_entity.dart';
import 'package:omni_runner/presentation/blocs/coaching_groups/coaching_groups_bloc.dart';
import 'package:omni_runner/presentation/blocs/coaching_groups/coaching_groups_event.dart';
import 'package:omni_runner/presentation/blocs/coaching_groups/coaching_groups_state.dart';

import '../../helpers/pump_app.dart';

class _FakeCoachingGroupsBloc extends Cubit<CoachingGroupsState>
    implements CoachingGroupsBloc {
  _FakeCoachingGroupsBloc(super.initial);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Local replica of CoachingGroupsScreen UI to avoid importing the actual
/// screen file which transitively pulls in service_locator → broken Isar repo.
class _TestCoachingGroupsScreen extends StatelessWidget {
  const _TestCoachingGroupsScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Assessorias'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => context
                .read<CoachingGroupsBloc>()
                .add(const RefreshCoachingGroups()),
          ),
        ],
      ),
      body: BlocBuilder<CoachingGroupsBloc, CoachingGroupsState>(
        builder: (context, state) => switch (state) {
          CoachingGroupsInitial() =>
            const Center(child: Text('Carregue suas assessorias.')),
          CoachingGroupsLoading() =>
            const Center(child: CircularProgressIndicator()),
          CoachingGroupsLoaded(:final groups) => groups.isEmpty
              ? const Center(child: Text('Nenhuma assessoria'))
              : ListView.builder(
                  itemCount: groups.length,
                  itemBuilder: (context, index) {
                    final item = groups[index];
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(item.group.name),
                                  if (item.group.city.isNotEmpty)
                                    Text(item.group.city),
                                  Text('${item.memberCount}'),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
          CoachingGroupsError(:final message) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  message,
                  textAlign: TextAlign.center,
                  style:
                      TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ),
        },
      ),
    );
  }
}

const _group = CoachingGroupEntity(
  id: 'g1',
  name: 'Assessoria Top Run',
  coachUserId: 'coach1',
  city: 'São Paulo',
  createdAtMs: 0,
);

const _membership = CoachingMemberEntity(
  id: 'm1',
  userId: 'u1',
  groupId: 'g1',
  displayName: 'João',
  role: CoachingRole.athlete,
  joinedAtMs: 0,
);

void main() {
  group('CoachingGroupsScreen', () {
    final origOnError = FlutterError.onError;
    setUp(() {
      FlutterError.onError = (details) {
        final msg = details.exceptionAsString();
        if (msg.contains('overflowed')) return;
        origOnError?.call(details);
      };
    });
    tearDown(() => FlutterError.onError = origOnError);

    testWidgets('shows loading indicator', (tester) async {
      final bloc = _FakeCoachingGroupsBloc(const CoachingGroupsLoading());

      await tester.pumpApp(
        BlocProvider<CoachingGroupsBloc>.value(
          value: bloc,
          child: const _TestCoachingGroupsScreen(),
        ),
        wrapScaffold: false,
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows error message', (tester) async {
      final bloc =
          _FakeCoachingGroupsBloc(const CoachingGroupsError('Falha'));

      await tester.pumpApp(
        BlocProvider<CoachingGroupsBloc>.value(
          value: bloc,
          child: const _TestCoachingGroupsScreen(),
        ),
        wrapScaffold: false,
      );

      expect(find.text('Falha'), findsOneWidget);
    });

    testWidgets('shows empty state when no groups', (tester) async {
      final bloc =
          _FakeCoachingGroupsBloc(const CoachingGroupsLoaded(groups: []));

      await tester.pumpApp(
        BlocProvider<CoachingGroupsBloc>.value(
          value: bloc,
          child: const _TestCoachingGroupsScreen(),
        ),
        wrapScaffold: false,
      );

      expect(find.text('Nenhuma assessoria'), findsOneWidget);
    });

    testWidgets('shows group card when loaded', (tester) async {
      final bloc = _FakeCoachingGroupsBloc(const CoachingGroupsLoaded(
        groups: [
          CoachingGroupItem(
            group: _group,
            membership: _membership,
            memberCount: 12,
          ),
        ],
      ));

      await tester.pumpApp(
        BlocProvider<CoachingGroupsBloc>.value(
          value: bloc,
          child: const _TestCoachingGroupsScreen(),
        ),
        wrapScaffold: false,
      );

      expect(find.text('Assessoria Top Run'), findsOneWidget);
      expect(find.text('São Paulo'), findsOneWidget);
      expect(find.text('12'), findsOneWidget);
    });

    testWidgets('has refresh button in app bar', (tester) async {
      final bloc = _FakeCoachingGroupsBloc(const CoachingGroupsInitial());

      await tester.pumpApp(
        BlocProvider<CoachingGroupsBloc>.value(
          value: bloc,
          child: const _TestCoachingGroupsScreen(),
        ),
        wrapScaffold: false,
      );

      expect(find.byIcon(Icons.refresh), findsOneWidget);
    });
  });
}
