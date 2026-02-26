import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:omni_runner/core/analytics/product_event_tracker.dart';
import 'package:omni_runner/core/auth/user_identity_provider.dart';
import 'package:omni_runner/core/push/notification_rules_service.dart';
import 'package:omni_runner/core/service_locator.dart';
import 'package:omni_runner/domain/entities/challenge_entity.dart';
import 'package:omni_runner/domain/entities/challenge_rules_entity.dart';
import 'package:omni_runner/presentation/blocs/challenges/challenges_bloc.dart';
import 'package:omni_runner/presentation/blocs/challenges/challenges_event.dart';
import 'package:omni_runner/presentation/blocs/challenges/challenges_state.dart';
import 'package:omni_runner/presentation/blocs/verification/verification_bloc.dart';
import 'package:omni_runner/presentation/blocs/verification/verification_event.dart';
import 'package:omni_runner/presentation/screens/challenge_invite_screen.dart';
import 'package:omni_runner/presentation/screens/matchmaking_screen.dart';
import 'package:omni_runner/presentation/widgets/success_overlay.dart';
import 'package:omni_runner/presentation/widgets/verification_gate.dart';

class ChallengeCreateScreen extends StatefulWidget {
  final ChallengeType? initialType;
  final ChallengeMetric? initialMetric;
  final int? initialWindowMin;
  final int? initialFee;
  final double? initialTarget;

  const ChallengeCreateScreen({
    super.key,
    this.initialType,
    this.initialMetric,
    this.initialWindowMin,
    this.initialFee,
    this.initialTarget,
  });

  @override
  State<ChallengeCreateScreen> createState() => _ChallengeCreateScreenState();
}

class _ChallengeCreateScreenState extends State<ChallengeCreateScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  late final TextEditingController _targetCtrl;
  late final TextEditingController _feeCtrl;

  final _verificationBloc = VerificationBloc()
    ..add(const LoadVerificationState());

  /// 0 = Agora, 1 = Agendado
  int _mode = 0;

  late ChallengeType _type;
  late ChallengeMetric _metric;
  bool _created = false;

  /// For "Agora" mode: window in minutes after accept
  late int _quickWindowMin;

  /// For group challenges: acceptance window in minutes
  int _acceptWindowMin = 10;

  /// Max participants for group challenges
  int _maxParticipants = 10;

  @override
  void initState() {
    super.initState();
    _type = widget.initialType ?? ChallengeType.oneVsOne;
    _metric = widget.initialMetric ?? ChallengeMetric.distance;
    _quickWindowMin = widget.initialWindowMin ?? 180;
    _feeCtrl = TextEditingController(
      text: '${widget.initialFee ?? 0}',
    );
    _targetCtrl = TextEditingController(
      text: widget.initialTarget != null && widget.initialTarget! > 0
          ? '${widget.initialTarget}'
          : '',
    );
  }

  /// For "Agendado" mode
  DateTime? _scheduledDate;
  TimeOfDay? _scheduledTime;
  int _windowDays = 7;

  @override
  void dispose() {
    if (!_created) {
      sl<ProductEventTracker>().track(ProductEvents.flowAbandoned, {
        'flow': 'challenge_create',
        'step': 'form',
      });
    }
    _verificationBloc.close();
    _titleCtrl.dispose();
    _targetCtrl.dispose();
    _feeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Criar Desafio')),
      body: BlocListener<ChallengesBloc, ChallengesState>(
        listener: (context, state) {
          if (state is ChallengeCreated) {
            _created = true;
            sl<ProductEventTracker>().trackOnce(
              ProductEvents.firstChallengeCreated,
              {'type': _type.name, 'metric': _metric.name},
            );
            sl<NotificationRulesService>().notifyChallengeReceived(
              challengeId: state.challenge.id,
            );
            showSuccessOverlay(context, message: 'Desafio criado!');
            Navigator.of(context).pushReplacement(
              MaterialPageRoute<void>(
                builder: (_) => BlocProvider.value(
                  value: context.read<ChallengesBloc>(),
                  child: ChallengeInviteScreen(
                    challenge: state.challenge,
                  ),
                ),
              ),
            );
          } else if (state is ChallengesError) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(state.message)),
            );
          }
        },
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Matchmaking CTA ──────────────────────────────────
                _MatchmakingBanner(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<String>(
                      builder: (_) => const MatchmakingScreen(),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // ── Mode selector ────────────────────────────────────
                Text('Quando?',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: _ModeCard(
                      icon: Icons.flash_on_rounded,
                      label: 'Agora',
                      description: 'Aceita → 5 min para se preparar → valendo!',
                      selected: _mode == 0,
                      onTap: () => setState(() => _mode = 0),
                    )),
                    const SizedBox(width: 10),
                    Expanded(child: _ModeCard(
                      icon: Icons.calendar_month_rounded,
                      label: 'Agendado',
                      description: 'Marque data e hora, corram de onde estiverem',
                      selected: _mode == 1,
                      onTap: () => setState(() => _mode = 1),
                    )),
                  ],
                ),
                const SizedBox(height: 20),

                // ── Title ────────────────────────────────────────────
                TextFormField(
                  controller: _titleCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nome do desafio (opcional)',
                    border: OutlineInputBorder(),
                    hintText: 'Ex: Corrida de domingo',
                  ),
                  maxLength: 60,
                ),
                const SizedBox(height: 12),

                // ── Type ─────────────────────────────────────────────
                Text('Tipo',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                SegmentedButton<ChallengeType>(
                  segments: const [
                    ButtonSegment(
                      value: ChallengeType.oneVsOne,
                      label: Text('1v1'),
                      icon: Icon(Icons.people),
                    ),
                    ButtonSegment(
                      value: ChallengeType.group,
                      label: Text('Grupo'),
                      icon: Icon(Icons.groups),
                    ),
                  ],
                  selected: {_type},
                  onSelectionChanged: (v) =>
                      setState(() => _type = v.first),
                ),
                if (_type == ChallengeType.group) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cs.primaryContainer.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline_rounded, size: 18, color: cs.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Crie um desafio cooperativo! O grupo trabalha junto '
                            'para atingir a meta coletiva. Se o grupo alcançar, todos ganham!',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(Icons.group, size: 20, color: cs.primary),
                      const SizedBox(width: 8),
                      Text('Máximo de participantes',
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w600)),
                      const Spacer(),
                      IconButton(
                        onPressed: _maxParticipants > 3
                            ? () => setState(() => _maxParticipants--)
                            : null,
                        icon: const Icon(Icons.remove_circle_outline),
                        iconSize: 24,
                      ),
                      Text('$_maxParticipants',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: cs.primary,
                          )),
                      IconButton(
                        onPressed: _maxParticipants < 100
                            ? () => setState(() => _maxParticipants++)
                            : null,
                        icon: const Icon(Icons.add_circle_outline),
                        iconSize: 24,
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),

                // ── Metric ───────────────────────────────────────────
                Text('O que vai contar?',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                SegmentedButton<ChallengeMetric>(
                  segments: const [
                    ButtonSegment(
                      value: ChallengeMetric.distance,
                      label: Text('Distância'),
                    ),
                    ButtonSegment(
                      value: ChallengeMetric.pace,
                      label: Text('Pace'),
                    ),
                    ButtonSegment(
                      value: ChallengeMetric.time,
                      label: Text('Tempo'),
                    ),
                  ],
                  selected: {_metric},
                  onSelectionChanged: (v) =>
                      setState(() => _metric = v.first),
                ),
                const SizedBox(height: 16),

                // ── Target distance ──────────────────────────────────
                TextFormField(
                  controller: _targetCtrl,
                  decoration: InputDecoration(
                    labelText: 'Meta ${_targetUnit()}',
                    border: const OutlineInputBorder(),
                    helperText: _type == ChallengeType.group
                        ? 'Soma coletiva do grupo. Vazio = qualquer corrida vale'
                        : 'Deixe vazio = quem fizer mais ganha',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
                  ],
                ),
                const SizedBox(height: 16),

                // ── Mode-specific fields ─────────────────────────────
                if (_mode == 0) _buildQuickFields(theme),
                if (_mode == 1) _buildScheduledFields(theme),

                // ── Group acceptance window ──────────────────────────
                if (_type == ChallengeType.group && _mode == 0) ...[
                  const SizedBox(height: 16),
                  _buildAcceptWindowFields(theme),
                ],

                const SizedBox(height: 16),

                // ── Entry fee ────────────────────────────────────────
                TextFormField(
                  controller: _feeCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Inscrição (OmniCoins)',
                    border: OutlineInputBorder(),
                    helperText: '0 = desafio gratuito',
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  onChanged: (_) => setState(() {}),
                  validator: (v) {
                    final fee = int.tryParse(v ?? '0') ?? 0;
                    if (fee < 0) return 'Valor inválido';
                    return null;
                  },
                ),
                if (_type == ChallengeType.group &&
                    (int.tryParse(_feeCtrl.text) ?? 0) > 0) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.warning_amber_rounded,
                            size: 18, color: Colors.orange.shade700),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Se o grupo não atingir a meta, a inscrição '
                            'não será devolvida. Só há reembolso se '
                            'ninguém correr.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.orange.shade800,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),

                // ── Validation rules summary ─────────────────────────
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Regras de validação',
                          style: theme.textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: cs.primary)),
                      const SizedBox(height: 6),
                      _ruleItem('Distância mínima por corrida: 1 km'),
                      _ruleItem('Apenas corridas verificadas contam'),
                      _ruleItem('Anti-cheat padrão ativado'),
                      if (_metric == ChallengeMetric.pace)
                        _ruleItem('Melhor pace de uma única sessão vence'),
                      if (_metric == ChallengeMetric.distance)
                        _ruleItem('Soma de todas as corridas no período'),
                      if (_metric == ChallengeMetric.time)
                        _ruleItem('Soma do tempo em movimento no período'),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // ── Submit ───────────────────────────────────────────
                FilledButton.icon(
                  icon: const Icon(Icons.emoji_events),
                  label: Text(_mode == 0
                      ? 'Criar Desafio'
                      : 'Criar Desafio Agendado'),
                  onPressed: _submit,
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Quick mode fields ──────────────────────────────────────────────────

  Widget _buildQuickFields(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Tempo para correr',
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text('Após o aceite, todos têm 5 minutos para se preparar. '
            'Depois, cada corredor terá esse tempo para completar suas corridas:',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.outline)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            _windowChip('1 hora', 60),
            _windowChip('3 horas', 180),
            _windowChip('6 horas', 360),
            _windowChip('12 horas', 720),
            _windowChip('24 horas', 1440),
          ],
        ),
      ],
    );
  }

  Widget _windowChip(String label, int minutes) {
    final selected = _quickWindowMin == minutes;
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => setState(() => _quickWindowMin = minutes),
      showCheckmark: false,
      selectedColor: Theme.of(context).colorScheme.primaryContainer,
      side: selected ? BorderSide.none : null,
      visualDensity: VisualDensity.compact,
    );
  }

  // ── Group acceptance window fields ─────────────────────────────────────

  Widget _buildAcceptWindowFields(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Tempo para aceitar',
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text('Todos os convidados terão esse tempo para aceitar. '
            'Quando todos aceitarem, a corrida inicia em 5 minutos.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.outline)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            _acceptChip('5 min', 5),
            _acceptChip('10 min', 10),
            _acceptChip('20 min', 20),
            _acceptChip('30 min', 30),
          ],
        ),
      ],
    );
  }

  Widget _acceptChip(String label, int minutes) {
    final selected = _acceptWindowMin == minutes;
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => setState(() => _acceptWindowMin = minutes),
      showCheckmark: false,
      selectedColor: Theme.of(context).colorScheme.secondaryContainer,
      side: selected ? BorderSide.none : null,
      visualDensity: VisualDensity.compact,
    );
  }

  // ── Scheduled mode fields ──────────────────────────────────────────────

  Widget _buildScheduledFields(ThemeData theme) {
    final cs = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Data e hora de início',
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.calendar_today, size: 18),
                label: Text(_scheduledDate != null
                    ? '${_scheduledDate!.day.toString().padLeft(2, '0')}/'
                        '${_scheduledDate!.month.toString().padLeft(2, '0')}/'
                        '${_scheduledDate!.year}'
                    : 'Escolher data'),
                onPressed: _pickDate,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.access_time, size: 18),
                label: Text(_scheduledTime != null
                    ? '${_scheduledTime!.hour.toString().padLeft(2, '0')}:'
                        '${_scheduledTime!.minute.toString().padLeft(2, '0')}'
                    : 'Escolher hora'),
                onPressed: _pickTime,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text('Duração do desafio',
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            _dayChip('1 dia', 1),
            _dayChip('3 dias', 3),
            _dayChip('7 dias', 7),
            _dayChip('14 dias', 14),
            _dayChip('30 dias', 30),
          ],
        ),
        if (_scheduledDate != null && _scheduledTime != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: cs.primaryContainer.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 16, color: cs.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'O desafio começa em '
                    '${_scheduledDate!.day.toString().padLeft(2, '0')}/'
                    '${_scheduledDate!.month.toString().padLeft(2, '0')} '
                    'às ${_scheduledTime!.hour.toString().padLeft(2, '0')}:'
                    '${_scheduledTime!.minute.toString().padLeft(2, '0')} '
                    'e dura $_windowDays ${_windowDays == 1 ? "dia" : "dias"}.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: cs.onPrimaryContainer),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _dayChip(String label, int days) {
    final selected = _windowDays == days;
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => setState(() => _windowDays = days),
      showCheckmark: false,
      selectedColor: Theme.of(context).colorScheme.primaryContainer,
      side: selected ? BorderSide.none : null,
      visualDensity: VisualDensity.compact,
    );
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      firstDate: now,
      lastDate: now.add(const Duration(days: 90)),
      initialDate: _scheduledDate ?? now.add(const Duration(days: 1)),
    );
    if (picked != null) setState(() => _scheduledDate = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _scheduledTime ?? const TimeOfDay(hour: 7, minute: 0),
    );
    if (picked != null) setState(() => _scheduledTime = picked);
  }

  // ── Helpers ────────────────────────────────────────────────────────────

  Widget _ruleItem(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(Icons.check, size: 14,
              color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 6),
          Flexible(
            child: Text(text,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
        ],
      ),
    );
  }

  String _targetUnit() => switch (_metric) {
        ChallengeMetric.distance => '(km)',
        ChallengeMetric.pace => '(min/km)',
        ChallengeMetric.time => '(min)',
      };

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    if (_mode == 1) {
      if (_scheduledDate == null || _scheduledTime == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Escolha a data e hora para agendar.')),
        );
        return;
      }
    }

    final fee = int.tryParse(_feeCtrl.text) ?? 0;

    // Monetization gate: stake > 0 requires VERIFIED status
    if (fee > 0) {
      final canProceed = await checkVerificationGate(
        context,
        verification: _verificationBloc.cached,
        entryFeeCoins: fee,
      );
      if (!canProceed) return;
    }
    final identity = sl<UserIdentityProvider>();
    final uid = identity.userId;
    final displayName = identity.displayName;

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

    final ChallengeStartMode startMode;
    int? fixedStartMs;
    int windowMs;

    if (_mode == 0) {
      startMode = ChallengeStartMode.onAccept;
      windowMs = _quickWindowMin * 60 * 1000;
    } else {
      startMode = ChallengeStartMode.scheduled;
      final dt = DateTime(
        _scheduledDate!.year,
        _scheduledDate!.month,
        _scheduledDate!.day,
        _scheduledTime!.hour,
        _scheduledTime!.minute,
      );
      fixedStartMs = dt.millisecondsSinceEpoch;
      windowMs = _windowDays * 86400000;
    }

    final rules = ChallengeRulesEntity(
      metric: _metric,
      target: target,
      windowMs: windowMs,
      startMode: startMode,
      fixedStartMs: fixedStartMs,
      entryFeeCoins: fee,
      acceptWindowMin: _type == ChallengeType.group && _mode == 0
          ? _acceptWindowMin
          : null,
      maxParticipants:
          _type == ChallengeType.group ? _maxParticipants : null,
    );

    final typeStr = switch (_type) {
      ChallengeType.oneVsOne => 'one_vs_one',
      ChallengeType.group => 'group',
      ChallengeType.teamVsTeam => 'team_vs_team',
    };

    if (!mounted) return;

    context.read<ChallengesBloc>().add(CreateChallengeRequested(
          creatorUserId: uid,
          creatorDisplayName: displayName,
          type: typeStr,
          rules: rules,
          title: _titleCtrl.text.isEmpty ? null : _titleCtrl.text,
        ));
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Mode card
// ═════════════════════════════════════════════════════════════════════════════

class _ModeCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String description;
  final bool selected;
  final VoidCallback onTap;

  const _ModeCard({
    required this.icon,
    required this.label,
    required this.description,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected
              ? cs.primaryContainer
              : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? cs.primary : Colors.transparent,
            width: 2,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, size: 28,
                color: selected ? cs.primary : cs.outline),
            const SizedBox(height: 6),
            Text(label,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: selected ? cs.primary : null,
                )),
            const SizedBox(height: 2),
            Text(description,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: cs.outline, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

class _MatchmakingBanner extends StatelessWidget {
  final VoidCallback onTap;
  const _MatchmakingBanner({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.tertiaryContainer,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: cs.tertiary.withValues(alpha: 0.15),
                ),
                child: Icon(Icons.sports_mma_rounded,
                    size: 22, color: cs.tertiary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Sem oponente? Use o matchmaking',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: cs.onTertiaryContainer,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Encontramos alguém do seu nível automaticamente',
                      style: TextStyle(
                          fontSize: 11, color: cs.onTertiaryContainer),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios,
                  size: 16, color: cs.onTertiaryContainer),
            ],
          ),
        ),
      ),
    );
  }
}
