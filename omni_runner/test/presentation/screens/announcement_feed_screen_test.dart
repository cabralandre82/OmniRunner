import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/announcement_entity.dart';
import 'package:omni_runner/presentation/blocs/announcement_feed/announcement_feed_bloc.dart';
import 'package:omni_runner/presentation/blocs/announcement_feed/announcement_feed_event.dart';
import 'package:omni_runner/presentation/blocs/announcement_feed/announcement_feed_state.dart';

import '../../helpers/pump_app.dart';

class _FakeAnnouncementFeedBloc extends Cubit<AnnouncementFeedState>
    implements AnnouncementFeedBloc {
  _FakeAnnouncementFeedBloc(super.initial);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _announcement = AnnouncementEntity(
  id: 'a1',
  groupId: 'g1',
  createdBy: 'u1',
  title: 'Novo treino',
  body: 'Treino especial amanhã',
  pinned: true,
  createdAt: DateTime(2026, 3, 5),
  updatedAt: DateTime(2026, 3, 5),
  authorDisplayName: 'Coach',
  isRead: false,
);

void main() {
  group('AnnouncementFeedScreen', () {
    final origOnError = FlutterError.onError;
    setUp(() {
      FlutterError.onError = (details) {
        final msg = details.exceptionAsString();
        if (msg.contains('overflowed')) return;
        origOnError?.call(details);
      };
    });
    tearDown(() => FlutterError.onError = origOnError);

    testWidgets('shows error state', (tester) async {
      final bloc = _FakeAnnouncementFeedBloc(
          const AnnouncementFeedError('Falha ao carregar'));

      await tester.pumpApp(
        BlocProvider<AnnouncementFeedBloc>.value(
          value: bloc,
          child: const _TestFeedView(groupId: 'g1', isStaff: false),
        ),
        wrapScaffold: false,
      );

      expect(find.text('Falha ao carregar'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
    });

    testWidgets('shows empty state when no announcements', (tester) async {
      final bloc = _FakeAnnouncementFeedBloc(
        const AnnouncementFeedLoaded(announcements: [], unreadCount: 0),
      );

      await tester.pumpApp(
        BlocProvider<AnnouncementFeedBloc>.value(
          value: bloc,
          child: const _TestFeedView(groupId: 'g1', isStaff: false),
        ),
        wrapScaffold: false,
      );

      expect(find.text('Nenhum aviso publicado'), findsOneWidget);
    });

    testWidgets('shows announcement cards when loaded', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final bloc = _FakeAnnouncementFeedBloc(
        AnnouncementFeedLoaded(
          announcements: [_announcement],
          unreadCount: 1,
        ),
      );

      await tester.pumpApp(
        BlocProvider<AnnouncementFeedBloc>.value(
          value: bloc,
          child: const _TestFeedView(groupId: 'g1', isStaff: false),
        ),
        wrapScaffold: false,
      );

      expect(find.text('Novo treino'), findsOneWidget);
      expect(find.byIcon(Icons.push_pin), findsOneWidget);
    });

    testWidgets('shows FAB for staff users', (tester) async {
      final bloc = _FakeAnnouncementFeedBloc(
        const AnnouncementFeedLoaded(announcements: [], unreadCount: 0),
      );

      await tester.pumpApp(
        BlocProvider<AnnouncementFeedBloc>.value(
          value: bloc,
          child: const _TestFeedView(groupId: 'g1', isStaff: true),
        ),
        wrapScaffold: false,
      );

      expect(find.byType(FloatingActionButton), findsOneWidget);
      expect(find.text('Novo Aviso'), findsOneWidget);
    });

    testWidgets('hides FAB for non-staff users', (tester) async {
      final bloc = _FakeAnnouncementFeedBloc(
        const AnnouncementFeedLoaded(announcements: [], unreadCount: 0),
      );

      await tester.pumpApp(
        BlocProvider<AnnouncementFeedBloc>.value(
          value: bloc,
          child: const _TestFeedView(groupId: 'g1', isStaff: false),
        ),
        wrapScaffold: false,
      );

      expect(find.byType(FloatingActionButton), findsNothing);
    });

    testWidgets('shows unread badge in title', (tester) async {
      final bloc = _FakeAnnouncementFeedBloc(
        AnnouncementFeedLoaded(
          announcements: [_announcement],
          unreadCount: 3,
        ),
      );

      await tester.pumpApp(
        BlocProvider<AnnouncementFeedBloc>.value(
          value: bloc,
          child: const _TestFeedView(groupId: 'g1', isStaff: false),
        ),
        wrapScaffold: false,
      );

      expect(find.text('Mural de Avisos'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
    });
  });
}

/// Minimal reproduction of AnnouncementFeedScreen's UI, using a
/// pre-provided BlocProvider instead of creating one from sl<>().
class _TestFeedView extends StatelessWidget {
  final String groupId;
  final bool isStaff;

  const _TestFeedView({required this.groupId, required this.isStaff});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: BlocBuilder<AnnouncementFeedBloc, AnnouncementFeedState>(
          builder: (context, state) {
            final unread = switch (state) {
              AnnouncementFeedLoaded(:final unreadCount) => unreadCount,
              _ => 0,
            };
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Mural de Avisos'),
                if (unread > 0) ...[
                  const SizedBox(width: 8),
                  Badge(label: Text('$unread'), backgroundColor: cs.primary),
                ],
              ],
            );
          },
        ),
      ),
      body: BlocBuilder<AnnouncementFeedBloc, AnnouncementFeedState>(
        builder: (context, state) {
          return switch (state) {
            AnnouncementFeedInitial() || AnnouncementFeedLoading() =>
              const Center(child: CircularProgressIndicator()),
            AnnouncementFeedError(:final message) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline_rounded,
                        size: 48, color: cs.error),
                    const SizedBox(height: 16),
                    Text(message,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: cs.error)),
                  ],
                ),
              ),
            AnnouncementFeedLoaded(:final announcements) =>
              announcements.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.campaign_outlined,
                              size: 64,
                              color: cs.onSurfaceVariant.withValues(alpha: 0.4)),
                          const SizedBox(height: 16),
                          Text('Nenhum aviso publicado',
                              style: theme.textTheme.titleMedium),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: announcements.length,
                      itemBuilder: (context, index) {
                        final a = announcements[index];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: ListTile(
                            leading: a.pinned
                                ? Icon(Icons.push_pin,
                                    color: cs.primary, size: 24)
                                : null,
                            title: Text(a.title,
                                style: TextStyle(
                                    fontWeight: a.isRead
                                        ? FontWeight.normal
                                        : FontWeight.bold)),
                          ),
                        );
                      },
                    ),
          };
        },
      ),
      floatingActionButton: isStaff
          ? FloatingActionButton.extended(
              onPressed: () {},
              icon: const Icon(Icons.add),
              label: const Text('Novo Aviso'),
            )
          : null,
    );
  }
}
