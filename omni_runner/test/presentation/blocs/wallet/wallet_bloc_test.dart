import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:omni_runner/domain/entities/ledger_entry_entity.dart';
import 'package:omni_runner/domain/entities/wallet_entity.dart';
import 'package:omni_runner/domain/repositories/i_ledger_repo.dart';
import 'package:omni_runner/domain/repositories/i_wallet_remote_source.dart';
import 'package:omni_runner/domain/repositories/i_wallet_repo.dart';
import 'package:omni_runner/presentation/blocs/wallet/wallet_bloc.dart';
import 'package:omni_runner/presentation/blocs/wallet/wallet_event.dart';
import 'package:omni_runner/presentation/blocs/wallet/wallet_state.dart';

class MockWalletRepo extends Mock implements IWalletRepo {}

class MockLedgerRepo extends Mock implements ILedgerRepo {}

class MockWalletRemoteSource extends Mock implements IWalletRemoteSource {}

const _userId = 'user-1';

const _wallet = WalletEntity(
  userId: _userId,
  balanceCoins: 500,
  lifetimeEarnedCoins: 1000,
  lifetimeSpentCoins: 500,
);

final _history = [
  const LedgerEntryEntity(
    id: 'e-1',
    userId: _userId,
    deltaCoins: 100,
    reason: LedgerReason.challengeOneVsOneWon,
    refId: 'ch-1',
    createdAtMs: 2000000,
  ),
  const LedgerEntryEntity(
    id: 'e-2',
    userId: _userId,
    deltaCoins: -50,
    reason: LedgerReason.challengeEntryFee,
    refId: 'ch-2',
    createdAtMs: 1000000,
  ),
];

Future<List<WalletState>> _collectStates(
  WalletBloc bloc, {
  required int count,
  Duration timeout = const Duration(seconds: 5),
}) async {
  final states = <WalletState>[];
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

void main() {
  late MockWalletRepo walletRepo;
  late MockLedgerRepo ledgerRepo;
  late MockWalletRemoteSource remote;

  setUpAll(() {
    registerFallbackValue(const WalletEntity(userId: ''));
    registerFallbackValue(const LedgerEntryEntity(
      id: '',
      userId: '',
      deltaCoins: 0,
      reason: LedgerReason.adminAdjustment,
      createdAtMs: 0,
    ));
  });

  setUp(() {
    walletRepo = MockWalletRepo();
    ledgerRepo = MockLedgerRepo();
    remote = MockWalletRemoteSource();

    // Default: remote returns null/empty (offline fallback)
    when(() => remote.fetchWallet(any())).thenAnswer((_) async => null);
    when(() => remote.fetchLedger(any())).thenAnswer((_) async => []);
  });

  WalletBloc buildBloc() => WalletBloc(
        walletRepo: walletRepo,
        ledgerRepo: ledgerRepo,
        remote: remote,
      );

  group('WalletBloc', () {
    test('initial state is WalletInitial', () {
      final bloc = buildBloc();
      expect(bloc.state, const WalletInitial());
      bloc.close();
    });

    group('LoadWallet', () {
      test('emits [Loading, Loaded] with wallet and history', () async {
        when(() => walletRepo.getByUserId(_userId))
            .thenAnswer((_) async => _wallet);
        when(() => ledgerRepo.getByUserId(_userId))
            .thenAnswer((_) async => _history);

        final bloc = buildBloc();
        final future = _collectStates(bloc, count: 2);
        bloc.add(const LoadWallet(_userId));
        final states = await future;

        expect(states[0], isA<WalletLoading>());
        expect(states[1], isA<WalletLoaded>());
        final loaded = states[1] as WalletLoaded;
        expect(loaded.wallet.balanceCoins, 500);
        expect(loaded.history.length, 2);
        await bloc.close();
      });

      test('emits [Loading, Error] on exception', () async {
        when(() => walletRepo.getByUserId(_userId))
            .thenThrow(Exception('db error'));
        when(() => ledgerRepo.getByUserId(_userId))
            .thenAnswer((_) async => []);

        final bloc = buildBloc();
        final future = _collectStates(bloc, count: 2);
        bloc.add(const LoadWallet(_userId));
        final states = await future;

        expect(states[0], isA<WalletLoading>());
        expect(states[1], isA<WalletError>());
        expect(
          (states[1] as WalletError).message,
          contains('Algo deu errado'),
        );
        await bloc.close();
      });
    });

    group('RefreshWallet', () {
      test('does nothing when userId is not set', () async {
        final bloc = buildBloc();
        final future = _collectStates(bloc, count: 1,
            timeout: const Duration(milliseconds: 200));
        bloc.add(const RefreshWallet());
        final states = await future;

        expect(states, isEmpty);
        await bloc.close();
      });

      test('re-fetches after LoadWallet sets userId', () async {
        when(() => walletRepo.getByUserId(_userId))
            .thenAnswer((_) async => _wallet);
        when(() => ledgerRepo.getByUserId(_userId))
            .thenAnswer((_) async => _history);

        final bloc = buildBloc();
        // Load first
        var future = _collectStates(bloc, count: 2);
        bloc.add(const LoadWallet(_userId));
        await future;

        // Now refresh
        final updatedWallet = _wallet.copyWith(balanceCoins: 999);
        when(() => walletRepo.getByUserId(_userId))
            .thenAnswer((_) async => updatedWallet);

        future = _collectStates(bloc, count: 1);
        bloc.add(const RefreshWallet());
        final states = await future;

        expect(states[0], isA<WalletLoaded>());
        expect((states[0] as WalletLoaded).wallet.balanceCoins, 999);
        await bloc.close();
      });
    });

    group('Remote sync', () {
      test('syncs remote wallet and ledger to local repos', () async {
        const remoteWallet = WalletEntity(
          userId: _userId,
          balanceCoins: 750,
          lifetimeEarnedCoins: 1500,
          lifetimeSpentCoins: 750,
        );
        final remoteLedger = [_history.first];

        when(() => remote.fetchWallet(_userId))
            .thenAnswer((_) async => remoteWallet);
        when(() => remote.fetchLedger(_userId))
            .thenAnswer((_) async => remoteLedger);
        when(() => walletRepo.save(remoteWallet))
            .thenAnswer((_) async {});
        when(() => ledgerRepo.append(any()))
            .thenAnswer((_) async {});
        when(() => walletRepo.getByUserId(_userId))
            .thenAnswer((_) async => remoteWallet);
        when(() => ledgerRepo.getByUserId(_userId))
            .thenAnswer((_) async => remoteLedger);

        final bloc = buildBloc();
        final future = _collectStates(bloc, count: 2);
        bloc.add(const LoadWallet(_userId));
        final states = await future;
        await bloc.close();

        verify(() => walletRepo.save(remoteWallet)).called(1);
        verify(() => ledgerRepo.append(any())).called(1);

        expect(states[1], isA<WalletLoaded>());
        final loaded = states[1] as WalletLoaded;
        expect(loaded.wallet.balanceCoins, 750);
      });

      test('falls back to local data when remote returns null', () async {
        when(() => remote.fetchWallet(_userId))
            .thenAnswer((_) async => null);
        when(() => remote.fetchLedger(_userId))
            .thenAnswer((_) async => []);
        when(() => walletRepo.getByUserId(_userId))
            .thenAnswer((_) async => _wallet);
        when(() => ledgerRepo.getByUserId(_userId))
            .thenAnswer((_) async => _history);

        final bloc = buildBloc();
        final future = _collectStates(bloc, count: 2);
        bloc.add(const LoadWallet(_userId));
        final states = await future;
        await bloc.close();

        verifyNever(() => walletRepo.save(any()));
        expect(states[1], isA<WalletLoaded>());
        expect((states[1] as WalletLoaded).wallet.balanceCoins, 500);
      });
    });
  });
}
