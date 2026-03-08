import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/challenge_entity.dart';
import 'package:omni_runner/domain/entities/challenge_participant_entity.dart';
import 'package:omni_runner/domain/entities/challenge_result_entity.dart';
import 'package:omni_runner/domain/entities/challenge_rules_entity.dart';
import 'package:omni_runner/domain/repositories/i_challenge_repo.dart';

final class InMemoryChallengeRepo implements IChallengeRepo {
  final _challenges = <String, ChallengeEntity>{};
  final _results = <String, ChallengeResultEntity>{};

  @override
  Future<void> save(ChallengeEntity challenge) async {
    _challenges[challenge.id] = challenge;
  }

  @override
  Future<ChallengeEntity?> getById(String id) async => _challenges[id];

  @override
  Future<List<ChallengeEntity>> getByUserId(String userId) async {
    return _challenges.values
        .where((c) => c.participants.any((p) => p.userId == userId))
        .toList()
      ..sort((a, b) => b.createdAtMs.compareTo(a.createdAtMs));
  }

  @override
  Future<List<ChallengeEntity>> getByStatus(ChallengeStatus status) async {
    return _challenges.values
        .where((c) => c.status == status)
        .toList()
      ..sort((a, b) => b.createdAtMs.compareTo(a.createdAtMs));
  }

  @override
  Future<void> update(ChallengeEntity challenge) async {
    _challenges[challenge.id] = challenge;
  }

  @override
  Future<void> deleteById(String id) async {
    _challenges.remove(id);
  }

  @override
  Future<void> saveResult(ChallengeResultEntity result) async {
    _results[result.challengeId] = result;
  }

  @override
  Future<ChallengeResultEntity?> getResultByChallengeId(
    String challengeId,
  ) async =>
      _results[challengeId];
}

ChallengeEntity _challenge({
  String id = 'c1',
  ChallengeStatus status = ChallengeStatus.pending,
  int createdAtMs = 1000,
  List<ChallengeParticipantEntity> participants = const [],
}) =>
    ChallengeEntity(
      id: id,
      creatorUserId: 'creator',
      status: status,
      type: ChallengeType.oneVsOne,
      rules: const ChallengeRulesEntity(
        goal: ChallengeGoal.mostDistance,
        target: 10000,
        windowMs: 86400000,
      ),
      participants: participants,
      createdAtMs: createdAtMs,
    );

ChallengeParticipantEntity _participant(String userId) =>
    ChallengeParticipantEntity(userId: userId, displayName: userId);

void main() {
  late InMemoryChallengeRepo repo;

  setUp(() => repo = InMemoryChallengeRepo());

  group('IChallengeRepo contract', () {
    test('save and getById round-trip', () async {
      final c = _challenge();
      await repo.save(c);
      expect(await repo.getById('c1'), equals(c));
    });

    test('getById returns null for missing', () async {
      expect(await repo.getById('nope'), isNull);
    });

    test('getByUserId returns challenges the user participates in', () async {
      await repo.save(_challenge(
        id: 'c1',
        participants: [_participant('u1'), _participant('u2')],
      ));
      await repo.save(_challenge(
        id: 'c2',
        participants: [_participant('u2')],
      ));
      await repo.save(_challenge(
        id: 'c3',
        participants: [_participant('u3')],
      ));

      final u2 = await repo.getByUserId('u2');
      expect(u2.length, 2);
      expect(u2.map((c) => c.id).toSet(), {'c1', 'c2'});
    });

    test('getByStatus filters correctly', () async {
      await repo.save(_challenge(id: 'p1', status: ChallengeStatus.pending));
      await repo.save(_challenge(id: 'a1', status: ChallengeStatus.active));
      await repo.save(_challenge(id: 'p2', status: ChallengeStatus.pending));

      final pending = await repo.getByStatus(ChallengeStatus.pending);
      expect(pending.length, 2);

      final active = await repo.getByStatus(ChallengeStatus.active);
      expect(active.length, 1);
    });

    test('update replaces challenge', () async {
      await repo.save(_challenge(status: ChallengeStatus.pending));
      await repo.update(_challenge(status: ChallengeStatus.active));

      final c = await repo.getById('c1');
      expect(c!.status, ChallengeStatus.active);
    });

    test('deleteById removes challenge', () async {
      await repo.save(_challenge());
      await repo.deleteById('c1');
      expect(await repo.getById('c1'), isNull);
    });

    test('saveResult and getResultByChallengeId round-trip', () async {
      const result = ChallengeResultEntity(
        challengeId: 'c1',
        goal: ChallengeGoal.mostDistance,
        results: [
          ParticipantResult(
            userId: 'u1',
            finalValue: 15000,
            rank: 1,
            outcome: ParticipantOutcome.won,
            coinsEarned: 50,
          ),
        ],
        totalCoinsDistributed: 50,
        calculatedAtMs: 9999,
      );

      await repo.saveResult(result);
      final found = await repo.getResultByChallengeId('c1');
      expect(found, equals(result));
    });

    test('getResultByChallengeId returns null when none', () async {
      expect(await repo.getResultByChallengeId('nope'), isNull);
    });
  });
}
