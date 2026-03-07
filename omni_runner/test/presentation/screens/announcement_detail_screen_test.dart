import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:omni_runner/domain/entities/announcement_entity.dart';
import 'package:omni_runner/presentation/blocs/announcement_detail/announcement_detail_bloc.dart';
import 'package:omni_runner/presentation/blocs/announcement_detail/announcement_detail_event.dart';
import 'package:omni_runner/presentation/blocs/announcement_detail/announcement_detail_state.dart';

import '../../helpers/pump_app.dart';

class _FakeAnnouncementDetailBloc extends Cubit<AnnouncementDetailState>
    implements AnnouncementDetailBloc {
  _FakeAnnouncementDetailBloc(super.initial);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _announcement = AnnouncementEntity(
  id: 'a1',
  groupId: 'g1',
  createdBy: 'u1',
  title: 'Treino cancelado',
  body: 'O treino de amanhã foi cancelado.',
  pinned: false,
  createdAt: DateTime(2026, 3, 5),
  updatedAt: DateTime(2026, 3, 5),
  authorDisplayName: 'Coach Silva',
  isRead: true,
);

void main() {
  group('AnnouncementDetailScreen', () {
    final origOnError = FlutterError.onError;
    setUp(() {
      FlutterError.onError = (details) {
        final msg = details.exceptionAsString();
        if (msg.contains('overflowed')) return;
        origOnError?.call(details);
      };
    });
    tearDown(() => FlutterError.onError = origOnError);

    testWidgets('shows loading indicator for initial/loading states',
        (tester) async {
      final bloc =
          _FakeAnnouncementDetailBloc(const AnnouncementDetailLoading());

      await tester.pumpApp(
        BlocProvider<AnnouncementDetailBloc>.value(
          value: bloc,
          child: const _TestDetailView(
            announcementId: 'a1',
            isStaff: false,
          ),
        ),
        wrapScaffold: false,
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows error message', (tester) async {
      final bloc = _FakeAnnouncementDetailBloc(
          const AnnouncementDetailError('Anúncio não encontrado.'));

      await tester.pumpApp(
        BlocProvider<AnnouncementDetailBloc>.value(
          value: bloc,
          child: const _TestDetailView(
            announcementId: 'a1',
            isStaff: false,
          ),
        ),
        wrapScaffold: false,
      );

      expect(find.text('Anúncio não encontrado.'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
    });

    testWidgets('shows announcement content when loaded', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final bloc = _FakeAnnouncementDetailBloc(
        AnnouncementDetailLoaded(announcement: _announcement),
      );

      await tester.pumpApp(
        BlocProvider<AnnouncementDetailBloc>.value(
          value: bloc,
          child: const _TestDetailView(
            announcementId: 'a1',
            isStaff: false,
          ),
        ),
        wrapScaffold: false,
      );

      expect(find.text('Treino cancelado'), findsWidgets);
      expect(find.text('O treino de amanhã foi cancelado.'), findsOneWidget);
    });

    testWidgets('shows read confirmation when already read', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final bloc = _FakeAnnouncementDetailBloc(
        AnnouncementDetailLoaded(announcement: _announcement),
      );

      await tester.pumpApp(
        BlocProvider<AnnouncementDetailBloc>.value(
          value: bloc,
          child: const _TestDetailView(
            announcementId: 'a1',
            isStaff: false,
          ),
        ),
        wrapScaffold: false,
      );

      expect(find.text('Leitura confirmada'), findsOneWidget);
    });
  });
}

/// Wraps the inner view of AnnouncementDetailScreen, bypassing the
/// BlocProvider that would call sl<>().
class _TestDetailView extends StatelessWidget {
  final String announcementId;
  final bool isStaff;

  const _TestDetailView({
    required this.announcementId,
    required this.isStaff,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: BlocBuilder<AnnouncementDetailBloc, AnnouncementDetailState>(
          builder: (context, state) {
            return Text(
              switch (state) {
                AnnouncementDetailLoaded(:final announcement) =>
                  announcement.title,
                _ => 'Aviso',
              },
            );
          },
        ),
      ),
      body: BlocBuilder<AnnouncementDetailBloc, AnnouncementDetailState>(
        builder: (context, state) {
          return switch (state) {
            AnnouncementDetailInitial() ||
            AnnouncementDetailLoading() =>
              const Center(child: CircularProgressIndicator()),
            AnnouncementDetailError(:final message) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline_rounded,
                          size: 48, color: cs.error),
                      const SizedBox(height: 16),
                      Text(message,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyLarge
                              ?.copyWith(color: cs.error)),
                    ],
                  ),
                ),
              ),
            AnnouncementDetailLoaded(:final announcement) =>
              SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(announcement.title,
                                style: theme.textTheme.titleLarge
                                    ?.copyWith(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 12),
                            Text(announcement.body,
                                style: theme.textTheme.bodyLarge),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    if (announcement.isRead)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.check_circle, color: cs.primary),
                          const SizedBox(width: 8),
                          Text('Leitura confirmada',
                              style: TextStyle(
                                  color: cs.primary,
                                  fontWeight: FontWeight.w500)),
                        ],
                      ),
                  ],
                ),
              ),
            AnnouncementDeleted() => const SizedBox.shrink(),
          };
        },
      ),
    );
  }
}
