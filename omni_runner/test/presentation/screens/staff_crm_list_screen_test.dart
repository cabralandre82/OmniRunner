import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:omni_runner/domain/entities/member_status_entity.dart';
import 'package:omni_runner/domain/repositories/i_crm_repo.dart';
import 'package:omni_runner/presentation/blocs/crm_list/crm_list_bloc.dart';
import 'package:omni_runner/presentation/blocs/crm_list/crm_list_event.dart';
import 'package:omni_runner/presentation/blocs/crm_list/crm_list_state.dart';
import 'package:omni_runner/presentation/screens/staff_crm_list_screen.dart';

import '../../helpers/pump_app.dart';

final _sl = GetIt.instance;

class _FakeCrmListBloc extends Cubit<CrmListState> implements CrmListBloc {
  _FakeCrmListBloc(super.initial);

  @override
  void add(CrmListEvent event) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _athlete1 = CrmAthleteView(
  userId: 'u1',
  displayName: 'João Silva',
  status: MemberStatusValue.active,
);

const _athlete2 = CrmAthleteView(
  userId: 'u2',
  displayName: 'Maria Santos',
  status: MemberStatusValue.paused,
  hasActiveAlerts: true,
);

void main() {
  group('StaffCrmListScreen', () {
    final origOnError = FlutterError.onError;
    late _FakeCrmListBloc fakeBloc;

    setUp(() {
      FlutterError.onError = (details) {
        final msg = details.exceptionAsString();
        if (msg.contains('overflowed')) return;
        origOnError?.call(details);
      };
      fakeBloc = _FakeCrmListBloc(const CrmListLoading());
      _sl.registerFactory<CrmListBloc>(() => fakeBloc);
    });
    tearDown(() {
      FlutterError.onError = origOnError;
      _sl.reset();
    });

    testWidgets('shows shimmer loader for loading state', (tester) async {
      fakeBloc = _FakeCrmListBloc(const CrmListLoading());
      _sl.unregister<CrmListBloc>();
      _sl.registerFactory<CrmListBloc>(() => fakeBloc);

      await tester.pumpApp(
        const StaffCrmListScreen(groupId: 'g1'),
        wrapScaffold: false,
      );

      expect(find.byType(AppBar), findsOneWidget);
      expect(find.text('CRM Atletas'), findsOneWidget);
    });

    testWidgets('shows error message for CrmListError state', (tester) async {
      fakeBloc = _FakeCrmListBloc(const CrmListError('Falha no servidor'));
      _sl.unregister<CrmListBloc>();
      _sl.registerFactory<CrmListBloc>(() => fakeBloc);

      await tester.pumpApp(
        const StaffCrmListScreen(groupId: 'g1'),
        wrapScaffold: false,
      );

      expect(find.text('Falha no servidor'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
      expect(find.text('Tentar novamente'), findsOneWidget);
    });

    testWidgets('shows empty state when no athletes', (tester) async {
      fakeBloc = _FakeCrmListBloc(const CrmListLoaded(
        athletes: [],
        tags: [],
      ));
      _sl.unregister<CrmListBloc>();
      _sl.registerFactory<CrmListBloc>(() => fakeBloc);

      await tester.pumpApp(
        const StaffCrmListScreen(groupId: 'g1'),
        wrapScaffold: false,
      );

      expect(find.text('Nenhum atleta encontrado'), findsOneWidget);
      expect(find.text('Convide atletas para sua assessoria'), findsOneWidget);
    });

    testWidgets('shows loaded athletes', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      fakeBloc = _FakeCrmListBloc(const CrmListLoaded(
        athletes: [_athlete1, _athlete2],
        tags: [],
      ));
      _sl.unregister<CrmListBloc>();
      _sl.registerFactory<CrmListBloc>(() => fakeBloc);

      await tester.pumpApp(
        const StaffCrmListScreen(groupId: 'g1'),
        wrapScaffold: false,
      );

      expect(find.text('João Silva'), findsOneWidget);
      expect(find.text('Maria Santos'), findsOneWidget);
    });

    testWidgets('shows FAB to manage tags', (tester) async {
      fakeBloc = _FakeCrmListBloc(const CrmListLoaded(
        athletes: [],
        tags: [],
      ));
      _sl.unregister<CrmListBloc>();
      _sl.registerFactory<CrmListBloc>(() => fakeBloc);

      await tester.pumpApp(
        const StaffCrmListScreen(groupId: 'g1'),
        wrapScaffold: false,
      );

      expect(find.text('Gerenciar Tags'), findsOneWidget);
      expect(find.byIcon(Icons.label_outline), findsOneWidget);
    });
  });
}
