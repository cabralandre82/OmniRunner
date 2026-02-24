import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:omni_runner/core/config/app_config.dart';
import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/domain/entities/challenge_rules_entity.dart';
import 'package:omni_runner/presentation/blocs/verification/verification_bloc.dart';
import 'package:omni_runner/presentation/blocs/verification/verification_event.dart';
import 'package:omni_runner/presentation/widgets/verification_gate.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Queue-based matchmaking screen.
///
/// Flow:
///   1. User configures intent (metric, target, duration, stake)
///   2. Taps "Buscar Oponente"
///   3. Shows searching animation + polls for match
///   4. Match found → navigates to challenge details
///   OR user cancels → returns to previous screen
class MatchmakingScreen extends StatefulWidget {
  const MatchmakingScreen({super.key});

  @override
  State<MatchmakingScreen> createState() => _MatchmakingScreenState();
}

enum _MatchState { setup, searching, matched, error }

class _MatchmakingScreenState extends State<MatchmakingScreen>
    with SingleTickerProviderStateMixin {
  static const _tag = 'Matchmaking';

  final _feeCtrl = TextEditingController(text: '0');
  final _targetCtrl = TextEditingController();
  final _verificationBloc = VerificationBloc()
    ..add(const LoadVerificationState());

  ChallengeMetric _metric = ChallengeMetric.distance;
  int _windowMin = 60;
  _MatchState _state = _MatchState.setup;
  String? _errorMsg;
  String? _queueId;
  String? _matchedChallengeId;
  String? _opponentName;
  String? _skillBracket;
  Timer? _pollTimer;
  late AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _pulseCtrl.dispose();
    _verificationBloc.close();
    _feeCtrl.dispose();
    _targetCtrl.dispose();
    super.dispose();
  }

  // ── API calls ────────────────────────────────────────────────────────────

  Future<void> _startMatchmaking() async {
    if (!AppConfig.isSupabaseReady) {
      _showError('Sem conexão com o servidor.');
      return;
    }

    final fee = int.tryParse(_feeCtrl.text) ?? 0;

    if (fee > 0) {
      final ok = await checkVerificationGate(
        context,
        verification: _verificationBloc.cached,
        entryFeeCoins: fee,
      );
      if (!ok) return;
    }

    double? target;
    if (_targetCtrl.text.isNotEmpty) {
      final raw = double.tryParse(_targetCtrl.text);
      if (raw != null && raw > 0) {
        target = switch (_metric) {
          ChallengeMetric.distance => raw * 1000,
          ChallengeMetric.pace => raw * 60,
          ChallengeMetric.time => raw * 60000,
        };
      }
    }

    setState(() {
      _state = _MatchState.searching;
      _errorMsg = null;
    });

    try {
      final res = await Supabase.instance.client.functions.invoke(
        'matchmake',
        body: {
          'action': 'queue',
          'metric': _metric.name,
          'target': target,
          'entry_fee_coins': fee,
          'window_ms': _windowMin * 60 * 1000,
        },
      );

      final data = res.data as Map<String, dynamic>?;
      if (data == null) {
        _showError('Resposta inválida do servidor.');
        return;
      }

      final innerData = data['data'] as Map<String, dynamic>? ?? data;
      final st = innerData['status'] as String?;

      if (st == 'matched') {
        _onMatchFound(innerData);
      } else if (st == 'queued') {
        setState(() {
          _queueId = innerData['queue_id'] as String?;
          _skillBracket = innerData['skill_bracket'] as String?;
        });
        _startPolling();
      } else {
        final errMsg = (data['error'] as Map?)?['message'] as String?;
        _showError(errMsg ?? 'Erro ao buscar oponente.');
      }
    } on Exception catch (e) {
      AppLogger.warn('Matchmake failed: $e', tag: _tag);
      _showError('Falha na conexão. Tente novamente.');
    }
  }

  void _onMatchFound(Map<String, dynamic> data) {
    _pollTimer?.cancel();
    final opp = data['opponent'] as Map<String, dynamic>?;
    setState(() {
      _state = _MatchState.matched;
      _matchedChallengeId = data['challenge_id'] as String?;
      _opponentName = opp?['display_name'] as String? ?? 'Oponente';
      _skillBracket = data['skill_bracket'] as String?;
    });
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (!mounted || _state != _MatchState.searching) {
        _pollTimer?.cancel();
        return;
      }
      try {
        final res = await Supabase.instance.client.functions.invoke(
          'matchmake',
          method: HttpMethod.get,
        );
        final data = res.data as Map<String, dynamic>?;
        final inner = data?['data'] as Map<String, dynamic>? ?? data;
        final entry = inner?['queue_entry'] as Map<String, dynamic>?;

        if (entry == null) return;

        if (entry['status'] == 'matched') {
          final challengeId = entry['matched_challenge_id'] as String?;
          if (challengeId != null) {
            _pollTimer?.cancel();
            // Get opponent name
            final oppId = entry['matched_with_user_id'] as String?;
            String oppName = 'Oponente';
            if (oppId != null) {
              try {
                final prof = await Supabase.instance.client
                    .from('profiles')
                    .select('display_name')
                    .eq('id', oppId)
                    .maybeSingle();
                oppName = prof?['display_name'] as String? ?? oppName;
              } on Exception catch (_) {}
            }
            if (!mounted) return;
            setState(() {
              _state = _MatchState.matched;
              _matchedChallengeId = challengeId;
              _opponentName = oppName;
            });
          }
        } else if (entry['status'] == 'expired') {
          _pollTimer?.cancel();
          if (!mounted) return;
          _showError('Tempo esgotado. Nenhum oponente encontrado.');
        }
      } on Exception catch (_) {
        // Polling failure — retry on next tick
      }
    });
  }

  Future<void> _cancelSearch() async {
    _pollTimer?.cancel();
    try {
      await Supabase.instance.client.functions.invoke(
        'matchmake',
        body: {'action': 'cancel'},
      );
    } on Exception catch (_) {}
    if (!mounted) return;
    setState(() => _state = _MatchState.setup);
  }

  void _showError(String msg) {
    if (!mounted) return;
    setState(() {
      _state = _MatchState.error;
      _errorMsg = msg;
    });
  }

  void _goToChallenge() {
    if (_matchedChallengeId == null) return;
    Navigator.of(context).pop(_matchedChallengeId);
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _state != _MatchState.searching,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _state == _MatchState.searching) {
          _cancelSearch();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Encontrar Oponente'),
          leading: _state == _MatchState.searching
              ? IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: _cancelSearch,
                )
              : null,
        ),
        body: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: switch (_state) {
            _MatchState.setup => _buildSetup(),
            _MatchState.searching => _buildSearching(),
            _MatchState.matched => _buildMatched(),
            _MatchState.error => _buildError(),
          },
        ),
      ),
    );
  }

  // ── Setup form ─────────────────────────────────────────────────────────

  Widget _buildSetup() {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return SingleChildScrollView(
      key: const ValueKey('setup'),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [cs.primaryContainer, cs.tertiaryContainer],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Icon(Icons.sports_mma_rounded, size: 40, color: cs.primary),
                const SizedBox(height: 8),
                Text(
                  'Matchmaking Automático',
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  'Configure seu desafio e encontraremos um oponente '
                  'do seu nível automaticamente.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Metric
          Text('O que vai contar?',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          SegmentedButton<ChallengeMetric>(
            segments: const [
              ButtonSegment(
                  value: ChallengeMetric.distance, label: Text('Distância')),
              ButtonSegment(
                  value: ChallengeMetric.pace, label: Text('Pace')),
              ButtonSegment(
                  value: ChallengeMetric.time, label: Text('Tempo')),
            ],
            selected: {_metric},
            onSelectionChanged: (v) => setState(() => _metric = v.first),
          ),
          const SizedBox(height: 16),

          // Target (optional)
          TextFormField(
            controller: _targetCtrl,
            decoration: InputDecoration(
              labelText: 'Meta ${_targetUnit()} (opcional)',
              border: const OutlineInputBorder(),
              helperText: 'Deixe vazio = quem fizer mais ganha',
            ),
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
            ],
          ),
          const SizedBox(height: 16),

          // Duration
          Text('Tempo para correr',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              _chip('30 min', 30),
              _chip('1 hora', 60),
              _chip('24 horas', 1440),
              _chip('3 dias', 4320),
              _chip('7 dias', 10080),
            ],
          ),
          const SizedBox(height: 16),

          // Entry fee
          TextFormField(
            controller: _feeCtrl,
            decoration: const InputDecoration(
              labelText: 'Aposta (OmniCoins)',
              border: OutlineInputBorder(),
              helperText: '0 = desafio gratuito',
            ),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          ),
          const SizedBox(height: 8),

          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 18, color: cs.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Você será pareado com alguém do seu nível, '
                    'mesma métrica e mesma aposta. Se não houver '
                    'oponente imediato, ficará na fila (expira em 24h).',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          FilledButton.icon(
            icon: const Icon(Icons.search_rounded),
            label: const Text('Buscar Oponente'),
            onPressed: _startMatchmaking,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              textStyle: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, int minutes) {
    final selected = _windowMin == minutes;
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => setState(() => _windowMin = minutes),
      showCheckmark: false,
      selectedColor: Theme.of(context).colorScheme.primaryContainer,
      side: selected ? BorderSide.none : null,
      visualDensity: VisualDensity.compact,
    );
  }

  String _targetUnit() => switch (_metric) {
        ChallengeMetric.distance => '(km)',
        ChallengeMetric.pace => '(min/km)',
        ChallengeMetric.time => '(min)',
      };

  // ── Searching animation ────────────────────────────────────────────────

  Widget _buildSearching() {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Center(
      key: const ValueKey('searching'),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: _pulseCtrl,
              builder: (_, __) {
                final scale = 1.0 + _pulseCtrl.value * 0.15;
                return Transform.scale(
                  scale: scale,
                  child: Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: cs.primaryContainer,
                      boxShadow: [
                        BoxShadow(
                          color: cs.primary.withValues(alpha: 0.3 * _pulseCtrl.value),
                          blurRadius: 30 * _pulseCtrl.value,
                          spreadRadius: 10 * _pulseCtrl.value,
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.sports_mma_rounded,
                      size: 50,
                      color: cs.primary,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 32),
            Text(
              'Buscando oponente...',
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (_skillBracket != null)
              Chip(
                avatar: Icon(Icons.trending_up, size: 16, color: cs.primary),
                label: Text('Nível: ${_bracketLabel(_skillBracket!)}'),
                backgroundColor: cs.surfaceContainerHighest,
              ),
            const SizedBox(height: 16),
            Text(
              'Procurando alguém com configurações compatíveis.\n'
              'Isso pode levar alguns segundos...',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 32),
            OutlinedButton.icon(
              icon: const Icon(Icons.close),
              label: const Text('Cancelar busca'),
              onPressed: _cancelSearch,
            ),
          ],
        ),
      ),
    );
  }

  // ── Match found ────────────────────────────────────────────────────────

  Widget _buildMatched() {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Center(
      key: const ValueKey('matched'),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.green.shade50,
                border: Border.all(color: Colors.green, width: 3),
              ),
              child: const Icon(
                Icons.check_circle_rounded,
                size: 60,
                color: Colors.green,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Oponente encontrado!',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: Colors.green.shade700,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(
                    backgroundColor: cs.primaryContainer,
                    child: Icon(Icons.person, color: cs.primary),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    _opponentName ?? 'Oponente',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              icon: const Icon(Icons.emoji_events_rounded),
              label: const Text('Ver Desafio'),
              onPressed: _goToChallenge,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                    horizontal: 32, vertical: 16),
                textStyle: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Error ──────────────────────────────────────────────────────────────

  Widget _buildError() {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Center(
      key: const ValueKey('error'),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, size: 64, color: cs.error),
            const SizedBox(height: 16),
            Text(
              _errorMsg ?? 'Ocorreu um erro.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(color: cs.error),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => setState(() => _state = _MatchState.setup),
              child: const Text('Tentar novamente'),
            ),
          ],
        ),
      ),
    );
  }

  String _bracketLabel(String bracket) => switch (bracket) {
        'beginner' => 'Iniciante',
        'intermediate' => 'Intermediário',
        'advanced' => 'Avançado',
        'elite' => 'Elite',
        _ => bracket,
      };
}
