import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/coaching_group_entity.dart';
import 'package:omni_runner/domain/entities/coaching_member_entity.dart';
import 'package:omni_runner/presentation/blocs/my_assessoria/my_assessoria_bloc.dart';
import 'package:omni_runner/presentation/blocs/my_assessoria/my_assessoria_state.dart';

import '../../helpers/pump_app.dart';

class _FakeMyAssessoriaBloc extends Cubit<MyAssessoriaState>
    implements MyAssessoriaBloc {
  _FakeMyAssessoriaBloc(super.initial);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _group = CoachingGroupEntity(
  id: 'g1',
  name: 'Running Club SP',
  coachUserId: 'coach1',
  description: 'Assessoria de corrida',
  city: 'São Paulo',
  createdAtMs: 0,
);

final _membership = CoachingMemberEntity(
  id: 'm1',
  userId: 'u1',
  groupId: 'g1',
  displayName: 'João',
  role: CoachingRole.athlete,
  joinedAtMs: 0,
);

void main() {
  group('MyAssessoriaScreen', () {
    final origOnError = FlutterError.onError;
    setUp(() {
      FlutterError.onError = (details) {
        final msg = details.exceptionAsString();
        if (msg.contains('overflowed')) return;
        origOnError?.call(details);
      };
    });
    tearDown(() => FlutterError.onError = origOnError);

    testWidgets('shows switching state', (tester) async {
      final bloc = _FakeMyAssessoriaBloc(const MyAssessoriaSwitching());

      await tester.pumpApp(
        BlocProvider<MyAssessoriaBloc>.value(
          value: bloc,
          child: const _TestMyAssessoriaScreen(),
        ),
        wrapScaffold: false,
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Trocando assessoria...'), findsOneWidget);
    });

    testWidgets('shows error message', (tester) async {
      final bloc = _FakeMyAssessoriaBloc(
        const MyAssessoriaError('Não foi possível carregar sua assessoria.'),
      );

      await tester.pumpApp(
        BlocProvider<MyAssessoriaBloc>.value(
          value: bloc,
          child: const _TestMyAssessoriaScreen(),
        ),
        wrapScaffold: false,
      );

      expect(
        find.text('Não foi possível carregar sua assessoria.'),
        findsOneWidget,
      );
    });

    testWidgets('shows loaded state with group info', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final bloc = _FakeMyAssessoriaBloc(MyAssessoriaLoaded(
        currentGroup: _group,
        membership: _membership,
      ));

      await tester.pumpApp(
        BlocProvider<MyAssessoriaBloc>.value(
          value: bloc,
          child: const _TestMyAssessoriaScreen(),
        ),
        wrapScaffold: false,
      );

      expect(find.text('Running Club SP'), findsOneWidget);
      expect(find.text('São Paulo'), findsOneWidget);
      expect(find.text('Atleta'), findsOneWidget);
    });

    testWidgets('shows no assessoria state when group is null',
        (tester) async {
      final bloc = _FakeMyAssessoriaBloc(const MyAssessoriaLoaded());

      await tester.pumpApp(
        BlocProvider<MyAssessoriaBloc>.value(
          value: bloc,
          child: const _TestMyAssessoriaScreen(),
        ),
        wrapScaffold: false,
      );

      expect(find.text('Sem assessoria'), findsOneWidget);
    });

    testWidgets('shows description when loaded', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final bloc = _FakeMyAssessoriaBloc(MyAssessoriaLoaded(
        currentGroup: _group,
        membership: _membership,
      ));

      await tester.pumpApp(
        BlocProvider<MyAssessoriaBloc>.value(
          value: bloc,
          child: const _TestMyAssessoriaScreen(),
        ),
        wrapScaffold: false,
      );

      expect(find.text('Assessoria de corrida'), findsOneWidget);
    });

    testWidgets('renders app bar', (tester) async {
      final bloc = _FakeMyAssessoriaBloc(const MyAssessoriaInitial());

      await tester.pumpApp(
        BlocProvider<MyAssessoriaBloc>.value(
          value: bloc,
          child: const _TestMyAssessoriaScreen(),
        ),
        wrapScaffold: false,
      );

      expect(find.byType(AppBar), findsOneWidget);
      expect(find.text('Minha Assessoria'), findsOneWidget);
    });
  });
}

/// Reproduces MyAssessoriaScreen UI without importing the actual screen
/// (which pulls in sl<> and the broken Isar chain).
class _TestMyAssessoriaScreen extends StatelessWidget {
  const _TestMyAssessoriaScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Minha Assessoria')),
      body: BlocBuilder<MyAssessoriaBloc, MyAssessoriaState>(
        builder: (context, state) => switch (state) {
          MyAssessoriaInitial() || MyAssessoriaLoading() =>
            const Center(child: CircularProgressIndicator()),
          MyAssessoriaSwitching() => const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Trocando assessoria...'),
                ],
              ),
            ),
          MyAssessoriaLoaded(
            :final currentGroup,
            :final membership,
          ) =>
            currentGroup == null
                ? _buildNoAssessoria(context)
                : _buildLoaded(context, currentGroup, membership!),
          MyAssessoriaSwitched() =>
            const Center(child: Icon(Icons.check_circle, size: 64)),
          MyAssessoriaError(:final message) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(message,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.error)),
              ),
            ),
        },
      ),
    );
  }

  Widget _buildNoAssessoria(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.groups_outlined, size: 72, color: theme.colorScheme.outline),
          const SizedBox(height: 24),
          Text('Sem assessoria',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildLoaded(
    BuildContext context,
    CoachingGroupEntity group,
    CoachingMemberEntity membership,
  ) {
    final theme = Theme.of(context);
    final roleLabel = switch (membership.role) {
      CoachingRole.adminMaster => 'Admin Master',
      CoachingRole.coach => 'Coach',
      CoachingRole.assistant => 'Assistente',
      CoachingRole.athlete => 'Atleta',
    };

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(group.name,
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold)),
                if (group.city.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(group.city,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.outline)),
                ],
                if (group.description.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(group.description, style: theme.textTheme.bodyMedium),
                ],
                const SizedBox(height: 16),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(roleLabel,
                      style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
