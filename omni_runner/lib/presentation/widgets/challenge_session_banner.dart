import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:omni_runner/core/service_locator.dart';

import 'package:omni_runner/core/router/app_router.dart';
import 'package:omni_runner/domain/repositories/i_challenge_repo.dart';
import 'package:omni_runner/core/logging/logger.dart';

/// Banner shown in [RunSummaryScreen] when the run was part of a challenge.
///
/// If the challenge is completed and results are available, shows a
/// "Ver resultado do desafio" button. Otherwise shows a status message.
class ChallengeSessionBanner extends StatefulWidget {
  final String challengeId;

  const ChallengeSessionBanner({super.key, required this.challengeId});

  @override
  State<ChallengeSessionBanner> createState() => _ChallengeSessionBannerState();
}

class _ChallengeSessionBannerState extends State<ChallengeSessionBanner> {
  bool _loading = true;
  bool _hasResult = false;
  String _statusText = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final repo = sl<IChallengeRepo>();
      final challenge = await repo.getById(widget.challengeId);

      // Fallback to Supabase if not in local Isar
      if (challenge == null) {
        try {
          final row = await sl<SupabaseClient>()
              .from('challenges')
              .select('id, status')
              .eq('id', widget.challengeId)
              .maybeSingle();
          if (row != null) {
            final statusStr = row['status'] as String? ?? '';
            if (!mounted) return;
            setState(() {
              _loading = false;
              _hasResult = statusStr == 'completed';
              _statusText = statusStr == 'completed'
                  ? 'Desafio concluído! Veja o resultado.'
                  : 'Sua corrida foi registrada no desafio. Resultado em breve.';
            });
            return;
          }
        } catch (e) {
      AppLogger.warn('Unexpected error', tag: 'ChallengeSessionBanner', error: e);
    }
      }
      if (!mounted || challenge == null) return;

      final result = await repo.getResultByChallengeId(widget.challengeId);

      if (!mounted) return;
      setState(() {
        _loading = false;
        _hasResult = result != null;
        _statusText = result != null
            ? 'Desafio concluído! Veja o resultado.'
            : 'Sua corrida foi registrada no desafio. Resultado em breve.';
      });
    } on Exception catch (e) {
      AppLogger.warn('Caught error', tag: 'ChallengeSessionBanner', error: e);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _statusText = 'Corrida registrada no desafio.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.teal.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.teal.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.emoji_events, size: 18, color: Colors.teal.shade700),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _statusText,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.teal.shade800,
                  ),
                ),
              ),
            ],
          ),
          if (_hasResult) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                label: const Text('Ver resultado do desafio'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.teal.shade700,
                  side: BorderSide(color: Colors.teal.shade300),
                ),
                onPressed: () async {
                  final repo = sl<IChallengeRepo>();
                  final challenge =
                      await repo.getById(widget.challengeId);
                  final result = await repo
                      .getResultByChallengeId(widget.challengeId);
                  if (!mounted || challenge == null || result == null) return;
                  if (!context.mounted) return;
                  context.push(
                    AppRoutes.challengeResult,
                    extra: ChallengeResultExtra(
                      challenge: challenge,
                      result: result,
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}
