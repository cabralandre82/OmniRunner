import 'package:flutter/material.dart';

import 'package:omni_runner/core/auth/user_identity_provider.dart';
import 'package:omni_runner/core/service_locator.dart';
import 'package:omni_runner/domain/entities/challenge_entity.dart';
import 'package:omni_runner/domain/entities/challenge_result_entity.dart';
import 'package:omni_runner/domain/entities/challenge_rules_entity.dart';
import 'package:omni_runner/domain/repositories/i_friendship_repo.dart';
import 'package:omni_runner/domain/usecases/social/send_friend_invite.dart';
import 'package:omni_runner/presentation/screens/challenge_create_screen.dart';
import 'package:omni_runner/presentation/screens/leaderboards_screen.dart';
import 'package:uuid/uuid.dart';

/// Post-challenge result screen.
///
/// Shows winner, participant metrics, reward status, and next-action CTAs.
/// Navigated from [ChallengeDetailsScreen] when challenge is completed,
/// or from [RunSummaryScreen] if the finished run settled a challenge.
class ChallengeResultScreen extends StatelessWidget {
  final ChallengeEntity challenge;
  final ChallengeResultEntity result;

  const ChallengeResultScreen({
    super.key,
    required this.challenge,
    required this.result,
  });

  @override
  Widget build(BuildContext context) {
    final uid = sl<UserIdentityProvider>().userId;
    final myResult = result.results
        .where((r) => r.userId == uid)
        .firstOrNull;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                children: [
                  _HeroSection(
                    challenge: challenge,
                    result: result,
                    myResult: myResult,
                    currentUserId: uid,
                  ),
                  const SizedBox(height: 16),
                  _ParticipantResults(
                    challenge: challenge,
                    result: result,
                    currentUserId: uid,
                  ),
                  const SizedBox(height: 16),
                  _RewardCard(
                    challenge: challenge,
                    result: result,
                    myResult: myResult,
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
            _CtaBar(challenge: challenge, currentUserId: uid),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Hero section — trophy/medal + outcome headline
// ═════════════════════════════════════════════════════════════════════════════

class _HeroSection extends StatelessWidget {
  final ChallengeEntity challenge;
  final ChallengeResultEntity result;
  final ParticipantResult? myResult;
  final String currentUserId;

  const _HeroSection({
    required this.challenge,
    required this.result,
    this.myResult,
    required this.currentUserId,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final outcome = myResult?.outcome;

    final isGroup = challenge.type == ChallengeType.group;
    final (icon, color, baseHeadline) = _outcomeVisuals(outcome);
    final headline = isGroup
        ? switch (outcome) {
            ParticipantOutcome.completedTarget =>
              'O grupo atingiu a meta!',
            ParticipantOutcome.participated =>
              'O grupo não atingiu a meta',
            ParticipantOutcome.didNotFinish =>
              'Ninguém correu',
            _ => baseHeadline,
          }
        : baseHeadline;

    final winners = result.winners;
    final isTeam = challenge.type == ChallengeType.teamVsTeam;

    String winnerLabel;
    if (isTeam && winners.isNotEmpty) {
      final winnerTeam = challenge.participants
          .where((p) => p.userId == winners.first.userId)
          .firstOrNull
          ?.team;
      if (winnerTeam == 'A') {
        winnerLabel = challenge.teamAGroupName ?? 'Equipe A';
      } else if (winnerTeam == 'B') {
        winnerLabel = challenge.teamBGroupName ?? 'Equipe B';
      } else {
        winnerLabel = 'Empate';
      }
      if (winners.first.outcome == ParticipantOutcome.tied) {
        winnerLabel = 'Empate';
      }
    } else {
      winnerLabel = winners
          .map((w) => _displayName(challenge, w.userId, currentUserId))
          .join(', ');
    }

    return Column(
      children: [
        const SizedBox(height: 12),
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withAlpha(30),
          ),
          child: Icon(icon, size: 44, color: color),
        ),
        const SizedBox(height: 12),
        Text(
          isTeam
              ? (outcome == ParticipantOutcome.won
                  ? 'Sua equipe venceu!'
                  : outcome == ParticipantOutcome.tied
                      ? 'Empate!'
                      : 'Sua equipe perdeu')
              : headline,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: color,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),
        Text(
          challenge.title ?? _defaultTitle(challenge),
          style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
        if (winners.isNotEmpty && outcome != ParticipantOutcome.won) ...[
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isTeam ? Icons.shield_rounded : Icons.emoji_events,
                size: 16,
                color: Colors.amber,
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  isTeam ? 'Equipe vencedora: $winnerLabel' : 'Vencedor: $winnerLabel',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  static (IconData, Color, String) _outcomeVisuals(ParticipantOutcome? o) =>
      switch (o) {
        ParticipantOutcome.won => (
            Icons.emoji_events,
            Colors.amber.shade700,
            'Você venceu!'
          ),
        ParticipantOutcome.tied => (
            Icons.handshake,
            Colors.blue.shade600,
            'Empate!'
          ),
        ParticipantOutcome.completedTarget => (
            Icons.check_circle,
            Colors.green.shade600,
            'Meta atingida!'
          ),
        ParticipantOutcome.lost => (
            Icons.sentiment_neutral,
            Colors.orange.shade600,
            'Boa tentativa!'
          ),
        ParticipantOutcome.participated => (
            Icons.directions_run,
            Colors.teal,
            'Você participou!'
          ),
        ParticipantOutcome.didNotFinish => (
            Icons.cancel_outlined,
            Colors.grey,
            'Não concluído'
          ),
        null => (Icons.help_outline, Colors.grey, 'Resultado'),
      };
}

// ═════════════════════════════════════════════════════════════════════════════
// Participant results table
// ═════════════════════════════════════════════════════════════════════════════

class _ParticipantResults extends StatelessWidget {
  final ChallengeEntity challenge;
  final ChallengeResultEntity result;
  final String currentUserId;

  const _ParticipantResults({
    required this.challenge,
    required this.result,
    required this.currentUserId,
  });

  @override
  Widget build(BuildContext context) {
    if (challenge.type == ChallengeType.teamVsTeam) {
      return _buildTeamResults(context);
    }
    if (challenge.type == ChallengeType.group) {
      return _buildGroupResults(context);
    }
    return _buildIndividualResults(context);
  }

  Widget _buildGroupResults(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final target = challenge.rules.target;
    final metric = result.metric;
    final lowerIsBetter = metric == ChallengeMetric.pace;

    final runners = result.results.where((r) => r.finalValue > 0).toList();

    final double collectiveValue;
    if (lowerIsBetter) {
      collectiveValue = runners.isEmpty
          ? 0
          : runners.map((r) => r.finalValue).reduce((a, b) => a + b) /
              runners.length;
    } else {
      collectiveValue = result.results
          .map((r) => r.finalValue)
          .fold(0.0, (a, b) => a + b);
    }

    final bool metTarget;
    if (target == null || target <= 0) {
      metTarget = runners.isNotEmpty;
    } else if (lowerIsBetter) {
      metTarget = collectiveValue > 0 && collectiveValue <= target;
    } else {
      metTarget = collectiveValue >= target;
    }

    final double progressFraction;
    if (target == null || target <= 0) {
      progressFraction = metTarget ? 1.0 : 0.0;
    } else if (lowerIsBetter) {
      progressFraction =
          collectiveValue <= 0 ? 0.0 : (target / collectiveValue).clamp(0.0, 1.0);
    } else {
      progressFraction = (collectiveValue / target).clamp(0.0, 1.0);
    }

    final progressColor = metTarget ? Colors.green : cs.primary;

    return Column(
      children: [
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.groups_rounded, size: 20, color: cs.primary),
                    const SizedBox(width: 8),
                    Text(
                      'Progresso Coletivo',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: progressFraction,
                    minHeight: 14,
                    backgroundColor: cs.surfaceContainerHighest,
                    color: progressColor,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      lowerIsBetter
                          ? 'Média: ${_formatValue(collectiveValue, metric)}'
                          : 'Total: ${_formatValue(collectiveValue, metric)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (target != null && target > 0)
                      Text(
                        'Meta: ${_formatValue(target, metric)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.outline,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: metTarget
                        ? Colors.green.withAlpha(20)
                        : Colors.orange.withAlpha(20),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        metTarget ? Icons.check_circle : Icons.cancel_outlined,
                        size: 16,
                        color: metTarget ? Colors.green.shade700 : Colors.orange.shade700,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        metTarget ? 'Meta atingida pelo grupo!' : 'Meta não atingida',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: metTarget
                              ? Colors.green.shade700
                              : Colors.orange.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.person_outline_rounded,
                        size: 20, color: cs.primary),
                    const SizedBox(width: 8),
                    Text(
                      'Contribuições',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ...result.results.map((pr) => _ResultRow(
                      pr: pr,
                      metric: result.metric,
                      isMe: pr.userId == currentUserId,
                      displayName:
                          _displayName(challenge, pr.userId, currentUserId),
                    )),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildIndividualResults(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.leaderboard_rounded,
                    size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('Classificação',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            ...result.results.map((pr) => _ResultRow(
                  pr: pr,
                  metric: result.metric,
                  isMe: pr.userId == currentUserId,
                  displayName:
                      _displayName(challenge, pr.userId, currentUserId),
                )),
          ],
        ),
      ),
    );
  }

  Widget _buildTeamResults(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final teamAId = challenge.teamAGroupId;
    final teamBId = challenge.teamBGroupId;
    final teamAName = challenge.teamAGroupName ?? 'Equipe A';
    final teamBName = challenge.teamBGroupName ?? 'Equipe B';

    final isIntraAssessoria = teamAId != null && teamBId != null && teamAId == teamBId;

    final teamAResults = result.results
        .where((r) => challenge.participants
            .any((p) => p.userId == r.userId &&
                (isIntraAssessoria ? p.team == 'A' : p.groupId == teamAId)))
        .toList();
    final teamBResults = result.results
        .where((r) => challenge.participants
            .any((p) => p.userId == r.userId &&
                (isIntraAssessoria ? p.team == 'B' : p.groupId == teamBId)))
        .toList();

    final lowerIsBetter = result.metric == ChallengeMetric.pace;

    double aggregateScore(List<ParticipantResult> team) {
      if (team.isEmpty) return 0;
      final sum = team.map((r) => r.finalValue).reduce((a, b) => a + b);
      if (lowerIsBetter) {
        final active = team.where((r) => r.finalValue > 0);
        return active.isEmpty ? 0 : sum / active.length;
      }
      return sum;
    }

    final scoreA = aggregateScore(teamAResults);
    final scoreB = aggregateScore(teamBResults);

    final teamAWon = teamAResults.isNotEmpty &&
        teamAResults.first.outcome == ParticipantOutcome.won;
    final teamBWon = teamBResults.isNotEmpty &&
        teamBResults.first.outcome == ParticipantOutcome.won;

    return Column(
      children: [
        // Team score comparison card
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(Icons.shield_rounded, size: 20, color: cs.primary),
                    const SizedBox(width: 8),
                    Text('Placar por Equipe',
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _TeamScoreColumn(
                        name: teamAName,
                        score: _formatValue(scoreA, result.metric),
                        isWinner: teamAWon,
                        memberCount: teamAResults.length,
                        theme: theme,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text('VS',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: cs.outline,
                          )),
                    ),
                    Expanded(
                      child: _TeamScoreColumn(
                        name: teamBName,
                        score: _formatValue(scoreB, result.metric),
                        isWinner: teamBWon,
                        memberCount: teamBResults.length,
                        theme: theme,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Team A members
        _TeamMemberCard(
          teamName: teamAName,
          isWinner: teamAWon,
          results: teamAResults,
          metric: result.metric,
          challenge: challenge,
          currentUserId: currentUserId,
          theme: theme,
        ),
        const SizedBox(height: 12),

        // Team B members
        _TeamMemberCard(
          teamName: teamBName,
          isWinner: teamBWon,
          results: teamBResults,
          metric: result.metric,
          challenge: challenge,
          currentUserId: currentUserId,
          theme: theme,
        ),
      ],
    );
  }
}

class _ResultRow extends StatelessWidget {
  final ParticipantResult pr;
  final ChallengeMetric metric;
  final bool isMe;
  final String displayName;

  const _ResultRow({
    required this.pr,
    required this.metric,
    required this.isMe,
    required this.displayName,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final (icon, iconColor) = switch (pr.outcome) {
      ParticipantOutcome.won => (Icons.emoji_events, Colors.amber.shade700),
      ParticipantOutcome.tied => (Icons.handshake, Colors.blue),
      ParticipantOutcome.completedTarget =>
        (Icons.check_circle, Colors.green),
      _ => (Icons.circle_outlined, Colors.grey),
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isMe
            ? theme.colorScheme.primary.withAlpha(15)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        border: isMe
            ? Border.all(color: theme.colorScheme.primary.withAlpha(40))
            : null,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: pr.rank != null
                ? Text(
                    '#${pr.rank}',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: pr.rank == 1 ? Colors.amber.shade700 : Colors.grey,
                    ),
                  )
                : Icon(icon, size: 18, color: iconColor),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    displayName,
                    style: TextStyle(
                      fontWeight: isMe ? FontWeight.bold : FontWeight.w500,
                      fontSize: 14,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isMe) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text('Você',
                        style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onPrimary, fontSize: 10)),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _formatValue(pr.finalValue, metric),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (pr.coinsEarned > 0) ...[
            const SizedBox(width: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '+${pr.coinsEarned}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Colors.green.shade700,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Team result widgets
// ═════════════════════════════════════════════════════════════════════════════

class _TeamScoreColumn extends StatelessWidget {
  final String name;
  final String score;
  final bool isWinner;
  final int memberCount;
  final ThemeData theme;

  const _TeamScoreColumn({
    required this.name,
    required this.score,
    required this.isWinner,
    required this.memberCount,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isWinner
            ? Colors.amber.withAlpha(20)
            : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: isWinner
            ? Border.all(color: Colors.amber.shade600, width: 1.5)
            : null,
      ),
      child: Column(
        children: [
          if (isWinner)
            Icon(Icons.emoji_events_rounded,
                size: 20, color: Colors.amber.shade700),
          Text(
            name,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            score,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: isWinner ? Colors.amber.shade800 : null,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 2),
          Text(
            '$memberCount ${memberCount == 1 ? 'atleta' : 'atletas'}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }
}

class _TeamMemberCard extends StatelessWidget {
  final String teamName;
  final bool isWinner;
  final List<ParticipantResult> results;
  final ChallengeMetric metric;
  final ChallengeEntity challenge;
  final String currentUserId;
  final ThemeData theme;

  const _TeamMemberCard({
    required this.teamName,
    required this.isWinner,
    required this.results,
    required this.metric,
    required this.challenge,
    required this.currentUserId,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isWinner ? Icons.emoji_events_rounded : Icons.shield_outlined,
                  size: 18,
                  color: isWinner ? Colors.amber.shade700 : Colors.grey,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    teamName,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isWinner)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.amber.withAlpha(25),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Vencedora',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.amber.shade800,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            if (results.isEmpty)
              Text('Nenhum atleta',
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline))
            else
              ...results.map((pr) => _ResultRow(
                    pr: pr,
                    metric: metric,
                    isMe: pr.userId == currentUserId,
                    displayName:
                        _displayName(challenge, pr.userId, currentUserId),
                  )),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Reward status card
// ═════════════════════════════════════════════════════════════════════════════

class _RewardCard extends StatelessWidget {
  final ChallengeEntity challenge;
  final ChallengeResultEntity result;
  final ParticipantResult? myResult;

  const _RewardCard({
    required this.challenge,
    required this.result,
    this.myResult,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCompleted = challenge.status == ChallengeStatus.completed;
    final myCoins = myResult?.coinsEarned ?? 0;
    final totalPool = result.totalCoinsDistributed;
    final hasStake = challenge.rules.entryFeeCoins > 0;

    if (!hasStake && isCompleted) {
      return const SizedBox.shrink();
    }

    final IconData statusIcon;
    final Color statusColor;
    final Color statusTextColor;
    final String statusLabel;
    final String statusSub;

    if (isCompleted) {
      statusIcon = Icons.check_circle;
      statusColor = Colors.green;
      statusTextColor = Colors.green.shade800;
      statusLabel = 'OmniCoins';
      statusSub = myCoins > 0
          ? 'Você ganhou $myCoins OmniCoins do desafio'
          : 'Você perdeu sua inscrição neste desafio';
    } else {
      statusIcon = Icons.hourglass_top_rounded;
      statusColor = Colors.orange;
      statusTextColor = Colors.orange.shade800;
      statusLabel = 'Resultado pendente';
      statusSub = 'O resultado está sendo processado.';
    }

    return Card(
      elevation: 0,
      color: statusColor.withAlpha(15),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: statusColor.withAlpha(50)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(statusIcon, color: statusColor, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    statusLabel,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: statusTextColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              statusSub,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (totalPool > 0 && isCompleted) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.toll_rounded,
                      size: 16, color: theme.colorScheme.outline),
                  const SizedBox(width: 4),
                  Text(
                    'Total distribuído: $totalPool OmniCoins',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Bottom CTA bar
// ═════════════════════════════════════════════════════════════════════════════

class _CtaBar extends StatelessWidget {
  final ChallengeEntity challenge;
  final String currentUserId;

  const _CtaBar({required this.challenge, required this.currentUserId});

  Future<void> _addFriend(BuildContext context) async {
    final opponents = challenge.participants
        .where((p) => p.userId != currentUserId)
        .toList();

    if (opponents.isEmpty) return;

    final targetId = opponents.length == 1
        ? opponents.first.userId
        : await showModalBottomSheet<String>(
            context: context,
            builder: (ctx) => SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Adicionar como amigo',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                  ...opponents.map((p) => ListTile(
                        leading: const CircleAvatar(
                            child: Icon(Icons.person)),
                        title: Text(p.displayName),
                        onTap: () => Navigator.pop(ctx, p.userId),
                      )),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          );

    if (targetId == null || !context.mounted) return;

    try {
      final sendInvite = SendFriendInvite(
        friendshipRepo: sl<IFriendshipRepo>(),
      );
      await sendInvite.call(
        fromUserId: currentUserId,
        toUserId: targetId,
        uuidGenerator: () => const Uuid().v4(),
        nowMs: DateTime.now().millisecondsSinceEpoch,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Convite de amizade enviado!')),
        );
      }
    } on Exception catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pad = MediaQuery.of(context).padding.bottom;

    return Container(
      padding: EdgeInsets.only(
          left: 16, right: 16, top: 12, bottom: pad + 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(15),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              icon: const Icon(Icons.replay_rounded, size: 18),
              label: const Text('Desafiar novamente'),
              onPressed: () {
                final windowMin = challenge.rules.windowMs ~/ 60000;
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute<void>(
                    builder: (_) => ChallengeCreateScreen(
                      initialType: challenge.type,
                      initialMetric: challenge.rules.metric,
                      initialWindowMin: windowMin,
                      initialFee: challenge.rules.entryFeeCoins,
                      initialTarget: challenge.rules.target,
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.leaderboard_rounded, size: 16),
                  label: const Text('Ranking'),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const LeaderboardsScreen(),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.person_add_rounded, size: 16),
                  label: const Text('Amigo'),
                  onPressed: () => _addFriend(context),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.share_rounded, size: 16),
                  label: const Text('Enviar'),
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Compartilhamento em breve!'),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Shared helpers
// ═════════════════════════════════════════════════════════════════════════════

String _displayName(
    ChallengeEntity challenge, String userId, String currentUserId) {
  if (userId == currentUserId) return 'Você';
  final participant = challenge.participants
      .where((p) => p.userId == userId)
      .firstOrNull;
  return participant?.displayName ?? 'Corredor';
}

String _defaultTitle(ChallengeEntity c) => switch (c.type) {
      ChallengeType.oneVsOne => 'Desafio 1v1',
      ChallengeType.teamVsTeam => 'Desafio de Equipe',
      ChallengeType.group => 'Desafio em Grupo',
    };

String _formatValue(double value, ChallengeMetric metric) => switch (metric) {
      ChallengeMetric.distance => '${(value / 1000).toStringAsFixed(2)} km',
      ChallengeMetric.pace => '${(value / 60).toStringAsFixed(1)} min/km',
      ChallengeMetric.time => '${(value / 60000).toStringAsFixed(0)} min',
    };
