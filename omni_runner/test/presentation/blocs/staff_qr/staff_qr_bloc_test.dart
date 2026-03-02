import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/core/errors/coaching_failures.dart';
import 'package:omni_runner/domain/entities/token_intent_entity.dart';
import 'package:omni_runner/domain/repositories/i_token_intent_repo.dart';
import 'package:omni_runner/presentation/blocs/staff_qr/staff_qr_bloc.dart';
import 'package:omni_runner/presentation/blocs/staff_qr/staff_qr_event.dart';
import 'package:omni_runner/presentation/blocs/staff_qr/staff_qr_state.dart';

final _payload = StaffQrPayload(
  intentId: 'int-1', type: TokenIntentType.issueToAthlete,
  groupId: 'g1', amount: 50, nonce: 'abc',
  expiresAtMs: DateTime.now().millisecondsSinceEpoch + 300000,
);

class _FakeRepo implements ITokenIntentRepo {
  bool shouldFail = false;
  @override
  Future<StaffQrPayload> createIntent({
    required TokenIntentType type, required String groupId, required int amount,
    String? targetUserId, String? championshipId,
  }) async {
    if (shouldFail) throw const TokenIntentFailed('server_error');
    return _payload;
  }
  @override
  Future<void> consumeIntent(StaffQrPayload payload) async {
    if (shouldFail) throw const TokenIntentFailed('already_consumed');
  }
  @override
  Future<EmissionCapacity> getEmissionCapacity(String groupId) async {
    if (shouldFail) throw Exception('network error');
    return const EmissionCapacity(
      availableTokens: 500,
      lifetimeIssued: 1200,
      lifetimeBurned: 700,
    );
  }
  @override
  Future<BadgeCapacity> getBadgeCapacity(String groupId) async {
    if (shouldFail) throw Exception('network error');
    return const BadgeCapacity(
      availableBadges: 15,
      lifetimePurchased: 50,
      lifetimeActivated: 35,
    );
  }
}

void main() {
  late _FakeRepo repo;
  setUp(() => repo = _FakeRepo());

  test('emits [Generating, Generated] on success', () async {
    final bloc = StaffQrBloc(repo: repo);
    final states = <StaffQrState>[];
    bloc.stream.listen(states.add);

    bloc.add(const GenerateQr(
      type: TokenIntentType.issueToAthlete, groupId: 'g1', amount: 50,
    ));
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(states, hasLength(2));
    expect(states[0], isA<StaffQrGenerating>());
    expect(states[1], isA<StaffQrGenerated>());

    await bloc.close();
  });

  test('emits [Generating, Error] on failure', () async {
    repo.shouldFail = true;
    final bloc = StaffQrBloc(repo: repo);
    final states = <StaffQrState>[];
    bloc.stream.listen(states.add);

    bloc.add(const GenerateQr(
      type: TokenIntentType.issueToAthlete, groupId: 'g1', amount: 50,
    ));
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(states, hasLength(2));
    expect(states[0], isA<StaffQrGenerating>());
    expect(states[1], isA<StaffQrError>());

    await bloc.close();
  });

  test('reset returns to initial', () async {
    final bloc = StaffQrBloc(repo: repo);
    final states = <StaffQrState>[];
    bloc.stream.listen(states.add);

    bloc.add(const ResetStaffQr());
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(states, hasLength(1));
    expect(states[0], isA<StaffQrInitial>());

    await bloc.close();
  });

  test('emits CapacityLoaded on LoadEmissionCapacity', () async {
    final bloc = StaffQrBloc(repo: repo);
    final states = <StaffQrState>[];
    bloc.stream.listen(states.add);

    bloc.add(const LoadEmissionCapacity('g1'));
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(states, hasLength(1));
    expect(states[0], isA<StaffQrCapacityLoaded>());
    final loaded = states[0] as StaffQrCapacityLoaded;
    expect(loaded.capacity.availableTokens, 500);
    expect(loaded.capacity.lifetimeIssued, 1200);
    expect(loaded.capacity.lifetimeBurned, 700);

    await bloc.close();
  });

  test('emits Error when LoadEmissionCapacity fails', () async {
    repo.shouldFail = true;
    final bloc = StaffQrBloc(repo: repo);
    final states = <StaffQrState>[];
    bloc.stream.listen(states.add);

    bloc.add(const LoadEmissionCapacity('g1'));
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(states, hasLength(1));
    expect(states[0], isA<StaffQrError>());

    await bloc.close();
  });

  test('emits BadgeCapacityLoaded on LoadBadgeCapacity', () async {
    final bloc = StaffQrBloc(repo: repo);
    final states = <StaffQrState>[];
    bloc.stream.listen(states.add);

    bloc.add(const LoadBadgeCapacity('g1'));
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(states, hasLength(1));
    expect(states[0], isA<StaffQrBadgeCapacityLoaded>());
    final loaded = states[0] as StaffQrBadgeCapacityLoaded;
    expect(loaded.capacity.availableBadges, 15);
    expect(loaded.capacity.lifetimePurchased, 50);
    expect(loaded.capacity.lifetimeActivated, 35);

    await bloc.close();
  });

  test('emits Error when LoadBadgeCapacity fails', () async {
    repo.shouldFail = true;
    final bloc = StaffQrBloc(repo: repo);
    final states = <StaffQrState>[];
    bloc.stream.listen(states.add);

    bloc.add(const LoadBadgeCapacity('g1'));
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(states, hasLength(1));
    expect(states[0], isA<StaffQrError>());

    await bloc.close();
  });
}
