/// E2E audit tests for the burn→clearing pipeline.
///
/// Covers: token intent entity, burn plan determinism, QR payload,
/// affiliation gating, idempotency, and compliance.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/token_intent_entity.dart';

// ─── Token / QR Payload ─────────────────────────────────────────────────

void main() {
  group('StaffQrPayload', () {
    test('encode/decode round-trip preserves all fields', () {
      final payload = StaffQrPayload(
        intentId: 'intent-abc',
        type: TokenIntentType.burnFromAthlete,
        groupId: 'group-xyz',
        amount: 42,
        nonce: 'nonce-123',
        expiresAtMs: 1900000000000,
      );

      final encoded = payload.encode();
      final decoded = StaffQrPayload.decode(encoded);

      expect(decoded.intentId, 'intent-abc');
      expect(decoded.type, TokenIntentType.burnFromAthlete);
      expect(decoded.groupId, 'group-xyz');
      expect(decoded.amount, 42);
      expect(decoded.nonce, 'nonce-123');
      expect(decoded.expiresAtMs, 1900000000000);
    });

    test('isExpired returns true when expiresAtMs is in the past', () {
      final payload = StaffQrPayload(
        intentId: 'i',
        type: TokenIntentType.burnFromAthlete,
        groupId: 'g',
        amount: 1,
        nonce: 'n',
        expiresAtMs: DateTime.now().millisecondsSinceEpoch - 10000,
      );

      expect(payload.isExpired, isTrue);
    });

    test('isExpired returns false when expiresAtMs is in the future', () {
      final payload = StaffQrPayload(
        intentId: 'i',
        type: TokenIntentType.burnFromAthlete,
        groupId: 'g',
        amount: 1,
        nonce: 'n',
        expiresAtMs: DateTime.now().millisecondsSinceEpoch + 300000,
      );

      expect(payload.isExpired, isFalse);
    });

    test('remainingDuration is zero when expired', () {
      final payload = StaffQrPayload(
        intentId: 'i',
        type: TokenIntentType.burnFromAthlete,
        groupId: 'g',
        amount: 1,
        nonce: 'n',
        expiresAtMs: DateTime.now().millisecondsSinceEpoch - 5000,
      );

      expect(payload.remainingDuration, Duration.zero);
    });

    test('decode throws FormatException on garbage input', () {
      expect(
        () => StaffQrPayload.decode('not-valid-base64!!!'),
        throwsA(isA<FormatException>()),
      );
    });

    test('decode throws on missing fields', () {
      final partial = base64Url.encode(utf8.encode(jsonEncode({'iid': 'x'})));
      expect(
        () => StaffQrPayload.decode(partial),
        throwsA(isA<TypeError>()),
      );
    });

    test('championshipId is preserved in round-trip', () {
      final payload = StaffQrPayload(
        intentId: 'i',
        type: TokenIntentType.champBadgeActivate,
        groupId: 'g',
        amount: 1,
        nonce: 'n',
        expiresAtMs: 1900000000000,
        championshipId: 'champ-001',
      );

      final decoded = StaffQrPayload.decode(payload.encode());
      expect(decoded.championshipId, 'champ-001');
    });

    test('championshipId is null when not provided', () {
      final payload = StaffQrPayload(
        intentId: 'i',
        type: TokenIntentType.burnFromAthlete,
        groupId: 'g',
        amount: 1,
        nonce: 'n',
        expiresAtMs: 1900000000000,
      );

      final decoded = StaffQrPayload.decode(payload.encode());
      expect(decoded.championshipId, isNull);
    });
  });

  // ─── Token intent type mapping ──────────────────────────────────────

  group('TokenIntentType', () {
    test('string round-trip for all types', () {
      for (final t in TokenIntentType.values) {
        final s = tokenIntentTypeToString(t);
        final back = tokenIntentTypeFromString(s);
        expect(back, t);
      }
    });

    test('fromString throws on unknown type', () {
      expect(
        () => tokenIntentTypeFromString('UNKNOWN_TYPE'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('all types have labels', () {
      for (final t in TokenIntentType.values) {
        expect(tokenIntentLabel(t), isNotEmpty);
      }
    });

    test('labels contain no monetary terms', () {
      final prohibited = RegExp(
        r'R\$|€|US\$|\bUSD\b|\bBRL\b|\bdinheiro\b|\bvalor\b|\bpreço\b',
        caseSensitive: false,
      );
      for (final t in TokenIntentType.values) {
        expect(prohibited.hasMatch(tokenIntentLabel(t)), isFalse,
            reason: 'Label for $t contains prohibited monetary term');
      }
    });
  });

  // ─── QR payload structure audit ─────────────────────────────────────

  group('QR payload structure (no money fields)', () {
    test('encoded JSON contains only coin-related keys', () {
      final payload = StaffQrPayload(
        intentId: 'i',
        type: TokenIntentType.burnFromAthlete,
        groupId: 'g',
        amount: 50,
        nonce: 'n',
        expiresAtMs: 1900000000000,
      );

      final json = payload.toJson();
      final keys = json.keys.toSet();

      // Allowed keys
      expect(keys, containsAll(['iid', 'typ', 'gid', 'amt', 'non', 'exp']));

      // Must NOT contain monetary fields
      for (final key in keys) {
        expect(key, isNot(contains('usd')));
        expect(key, isNot(contains('price')));
        expect(key, isNot(contains('fee')));
        expect(key, isNot(contains('money')));
        expect(key, isNot(contains('payment')));
      }
    });
  });

  // ─── Burn plan determinism (simulated) ──────────────────────────────

  group('Burn plan determinism (model simulation)', () {
    /// Simulates compute_burn_plan logic in Dart for testing determinism.
    List<Map<String, dynamic>> simulateBurnPlan({
      required Map<String, int> balancesByIssuer,
      required String redeemerGroupId,
      required int amount,
    }) {
      final result = <Map<String, dynamic>>[];
      var remaining = amount;

      // Sort: redeemer first, then others by balance desc
      final sorted = balancesByIssuer.entries.toList()
        ..sort((a, b) {
          final aIsRedeemer = a.key == redeemerGroupId ? 0 : 1;
          final bIsRedeemer = b.key == redeemerGroupId ? 0 : 1;
          if (aIsRedeemer != bIsRedeemer) return aIsRedeemer - bIsRedeemer;
          return b.value - a.value;
        });

      for (final entry in sorted) {
        if (remaining <= 0) break;
        if (entry.value <= 0) continue;
        final take = entry.value < remaining ? entry.value : remaining;
        remaining -= take;
        result.add({'issuer_group_id': entry.key, 'amount': take});
      }

      if (remaining > 0) {
        throw StateError('BURN_PLAN_SHORTFALL: remaining=$remaining');
      }
      return result;
    }

    test('prioritizes same-club coins first', () {
      final plan = simulateBurnPlan(
        balancesByIssuer: {'club-A': 10, 'club-B': 50, 'club-C': 5},
        redeemerGroupId: 'club-A',
        amount: 40,
      );

      expect(plan[0]['issuer_group_id'], 'club-A');
      expect(plan[0]['amount'], 10);
      expect(plan[1]['issuer_group_id'], 'club-B');
      expect(plan[1]['amount'], 30);
    });

    test('is deterministic (same input → same output)', () {
      final input = {
        'balancesByIssuer': {'A': 20, 'B': 30, 'C': 15},
        'redeemerGroupId': 'B',
        'amount': 50,
      };

      final plan1 = simulateBurnPlan(
        balancesByIssuer: Map<String, int>.from(input['balancesByIssuer'] as Map),
        redeemerGroupId: input['redeemerGroupId'] as String,
        amount: input['amount'] as int,
      );
      final plan2 = simulateBurnPlan(
        balancesByIssuer: Map<String, int>.from(input['balancesByIssuer'] as Map),
        redeemerGroupId: input['redeemerGroupId'] as String,
        amount: input['amount'] as int,
      );

      expect(plan1.length, plan2.length);
      for (var i = 0; i < plan1.length; i++) {
        expect(plan1[i]['issuer_group_id'], plan2[i]['issuer_group_id']);
        expect(plan1[i]['amount'], plan2[i]['amount']);
      }
    });

    test('never produces negative amounts', () {
      final plan = simulateBurnPlan(
        balancesByIssuer: {'A': 100, 'B': 50},
        redeemerGroupId: 'A',
        amount: 120,
      );

      for (final entry in plan) {
        expect(entry['amount'] as int, greaterThan(0));
      }
    });

    test('never exceeds per-issuer balance', () {
      final balances = {'A': 10, 'B': 50, 'C': 5};
      final plan = simulateBurnPlan(
        balancesByIssuer: Map<String, int>.from(balances),
        redeemerGroupId: 'A',
        amount: 40,
      );

      for (final entry in plan) {
        final issuer = entry['issuer_group_id'] as String;
        final amount = entry['amount'] as int;
        expect(amount, lessThanOrEqualTo(balances[issuer]!));
      }
    });

    test('throws when insufficient balance', () {
      expect(
        () => simulateBurnPlan(
          balancesByIssuer: {'A': 10, 'B': 5},
          redeemerGroupId: 'A',
          amount: 20,
        ),
        throwsStateError,
      );
    });

    test('total burned equals requested amount', () {
      final plan = simulateBurnPlan(
        balancesByIssuer: {'A': 100, 'B': 50, 'C': 30},
        redeemerGroupId: 'B',
        amount: 150,
      );

      final total = plan.fold<int>(
          0, (sum, e) => sum + (e['amount'] as int));
      expect(total, 150);
    });

    test('handles single-issuer burn (all intra-club)', () {
      final plan = simulateBurnPlan(
        balancesByIssuer: {'A': 100},
        redeemerGroupId: 'A',
        amount: 50,
      );

      expect(plan.length, 1);
      expect(plan[0]['issuer_group_id'], 'A');
      expect(plan[0]['amount'], 50);
    });
  });

  // ─── Clearing fee calculation ─────────────────────────────────────

  group('Clearing fee calculation', () {
    double calculateFee(double gross, double ratePercent) {
      return (gross * ratePercent / 100 * 100).roundToDouble() / 100;
    }

    test('3% of 100 coins = 3.00 fee', () {
      expect(calculateFee(100, 3.0), 3.0);
    });

    test('3% of 60 coins = 1.80 fee', () {
      expect(calculateFee(60, 3.0), 1.80);
    });

    test('3% of 1 coin = 0.03 fee', () {
      expect(calculateFee(1, 3.0), 0.03);
    });

    test('0% fee = 0.00', () {
      expect(calculateFee(1000, 0.0), 0.0);
    });

    test('net = gross - fee', () {
      final gross = 100.0;
      final fee = calculateFee(gross, 3.0);
      final net = gross - fee;
      expect(net, 97.0);
    });
  });
}
