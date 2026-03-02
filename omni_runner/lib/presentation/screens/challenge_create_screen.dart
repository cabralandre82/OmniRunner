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
import 'package:omni_runner/presentation/widgets/contextual_tip_banner.dart';
import 'package:omni_runner/core/tips/first_use_tips.dart';
import 'package:omni_runner/presentation/widgets/verification_gate.dart';

class ChallengeCreateScreen extends StatefulWidget {
  final ChallengeType? initialType;
  final ChallengeGoal? initialGoal;
  final int? initialWindowMin;
  final int? initialFee;
  final double? initialTarget;

  const ChallengeCreateScreen({
    super.key,
    this.initialType,
    this.initialGoal,
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

  final _verificationBloc = sl<VerificationBloc>()
    ..add(const LoadVerificationState());

  /// 0 = Agora, 1 = Agendado
  int _mode = 0;

  late ChallengeType _type;
  late ChallengeGoal _goal;
  bool _created = false;

  late int _quickWindowMin;

  int _acceptWindowMin = 10;
  int _maxParticipants = 10;

  @override
  void initState() {
    super.initState();
    _type = widget.initialType ?? ChallengeType.oneVsOne;
    _goal = widget.initialGoal ?? ChallengeGoal.fastestAtDistance;
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
              {'type': _type.name, 'goal': _goal.name},
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
                Text('Quem participa?',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                SegmentedButton<ChallengeType>(
                  segments: const [
                    ButtonSegment(
                      value: ChallengeType.oneVsOne,
                      label: Text('1 vs 1'),
                      icon: Icon(Icons.people),
                    ),
                    ButtonSegment(
                      value: ChallengeType.group,
                      label: Text('Grupo'),
                      icon: Icon(Icons.groups),
                    ),
                    ButtonSegment(
                      value: ChallengeType.team,
                      label: Text('Time'),
                      icon: Icon(Icons.shield_rounded),
                    ),
                  ],
                  selected: {_type},
                  onSelectionChanged: (v) {
                    setState(() {
                      _type = v.first;
                      if (_type != ChallengeType.team &&
                          _goal == ChallengeGoal.collectiveDistance) {
                        _goal = ChallengeGoal.fastestAtDistance;
                      }
                    });
                  },
                ),
                const SizedBox(height: 8),
                _TypeInfoBox(type: _type),
                if (_type == ChallengeType.group || _type == ChallengeType.team) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(Icons.group, size: 20, color: cs.primary),
                      const SizedBox(width: 8),
                      Text(_type == ChallengeType.team
                          ? 'Atletas por time'
                          : 'Máximo de participantes',
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

                // ── Goal ─────────────────────────────────────────────
                Text('Objetivo do desafio',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                _GoalCard(
                  icon: Icons.speed_rounded,
                  title: 'Quem corre X km mais rápido?',
                  subtitle: 'Você define a distância (ex: 10 km). '
                      'Vence quem completar no menor tempo em uma única corrida.',
                  selected: _goal == ChallengeGoal.fastestAtDistance,
                  onTap: () => setState(() => _goal = ChallengeGoal.fastestAtDistance),
                ),
                const SizedBox(height: 8),
                _GoalCard(
                  icon: Icons.straighten_rounded,
                  title: 'Quem corre mais km no período?',
                  subtitle: 'Todas as corridas somam. '
                      'Vence quem acumular mais quilômetros dentro do prazo.',
                  selected: _goal == ChallengeGoal.mostDistance,
                  onTap: () => setState(() => _goal = ChallengeGoal.mostDistance),
                ),
                const SizedBox(height: 8),
                _GoalCard(
                  icon: Icons.timer_rounded,
                  title: 'Quem faz melhor pace nos X km?',
                  subtitle: 'Você define a distância mínima (ex: 5 km). '
                      'Vence quem tiver o melhor pace médio numa corrida que cubra essa distância.',
                  selected: _goal == ChallengeGoal.bestPaceAtDistance,
                  onTap: () => setState(() => _goal = ChallengeGoal.bestPaceAtDistance),
                ),
                if (_type == ChallengeType.team) ...[
                  const SizedBox(height: 8),
                  _GoalCard(
                    icon: Icons.handshake_rounded,
                    title: 'Completar X km juntos!',
                    subtitle: 'Cooperativo por time — cada time soma seus km internamente. '
                        'O time que acumular mais km (ou atingir a meta primeiro) vence e leva os coins do outro.',
                    selected: _goal == ChallengeGoal.collectiveDistance,
                    onTap: () => setState(() => _goal = ChallengeGoal.collectiveDistance),
                  ),
                ],
                const SizedBox(height: 12),
                _WinnerExplainerBox(goal: _goal, type: _type),
                const SizedBox(height: 16),

                // ── Target distance ──────────────────────────────────
                TextFormField(
                  controller: _targetCtrl,
                  decoration: InputDecoration(
                    labelText: _targetLabel(),
                    border: const OutlineInputBorder(),
                    helperText: _targetHelper(),
                    suffixText: 'km',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
                  ],
                  validator: (v) {
                    if (_goalRequiresTarget() && (v == null || v.isEmpty)) {
                      return 'Distância obrigatória para esse tipo de desafio';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // ── Mode-specific fields ─────────────────────────────
                if (_mode == 0) _buildQuickFields(theme),
                if (_mode == 1) _buildScheduledFields(theme),

                // ── Group acceptance window ──────────────────────────
                if ((_type == ChallengeType.group || _type == ChallengeType.team) && _mode == 0) ...[
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
                    if (fee < 0) return 'Quantidade inválida';
                    return null;
                  },
                ),
                if ((int.tryParse(_feeCtrl.text) ?? 0) > 0)
                  const ContextualTipBanner(
                    tipKey: TipKey.firstStakeChallenge,
                    message: 'OmniCoins são debitadas da sua carteira ao '
                        'criar o desafio. O vencedor leva o pool de '
                        'inscrições de todos os participantes.',
                    icon: Icons.monetization_on_rounded,
                    color: Color(0xFFFFA000),
                  ),
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
                      ..._goalRules(),
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

  // ── Goal-specific rules ──────────────────────────────────────────────

  List<Widget> _goalRules() {
    final base = switch (_goal) {
      ChallengeGoal.fastestAtDistance => [
        _ruleItem('Cada atleta faz UMA corrida cobrindo a distância'),
        _ruleItem('Vence quem terminar essa corrida no menor tempo'),
      ],
      ChallengeGoal.mostDistance => [
        _ruleItem('Pode correr quantas vezes quiser no período'),
        _ruleItem('Vence quem acumular mais km somando todas as corridas'),
      ],
      ChallengeGoal.bestPaceAtDistance => [
        _ruleItem('Cada atleta faz UMA corrida cobrindo a distância mínima'),
        _ruleItem('Vence quem tiver o menor pace médio (min/km) nessa corrida'),
      ],
      ChallengeGoal.collectiveDistance => [
        _ruleItem('Cada membro corre o que puder — os km do time somam'),
        _ruleItem('O time com mais km totais vence e leva os coins do outro'),
      ],
    };
    if (_type == ChallengeType.team) {
      base.add(_ruleItem('Times com o mesmo número de atletas'));
      base.add(_ruleItem(
        _goal == ChallengeGoal.fastestAtDistance
            ? 'Tempo do time = tempo do último membro a completar'
            : _goal == ChallengeGoal.mostDistance
                ? 'Km do time = soma dos km de todos os membros'
                : 'Pace do time = média dos paces de todos os membros',
      ));
    }
    return base;
  }

  String _targetLabel() => switch (_goal) {
    ChallengeGoal.fastestAtDistance => 'Distância da corrida (obrigatório)',
    ChallengeGoal.mostDistance => 'Meta em km (opcional)',
    ChallengeGoal.bestPaceAtDistance => 'Distância mínima da corrida (obrigatório)',
    ChallengeGoal.collectiveDistance => 'Meta coletiva em km (obrigatório)',
  };

  String _targetHelper() => switch (_goal) {
    ChallengeGoal.fastestAtDistance =>
      'Ex: 10 = corrida de 10 km. Ganha quem completar essa distância no menor tempo.',
    ChallengeGoal.mostDistance =>
      'Opcional. Sem meta = ganha quem acumular mais km no período. '
      'Com meta = ganha quem atingir primeiro.',
    ChallengeGoal.bestPaceAtDistance =>
      'Ex: 5 = corrida de no mínimo 5 km. Ganha quem tiver o menor pace médio.',
    ChallengeGoal.collectiveDistance =>
      'Ex: 200 = o grupo precisa somar 200 km entre todos os membros.',
  };

  bool _goalRequiresTarget() =>
    _goal == ChallengeGoal.fastestAtDistance ||
    _goal == ChallengeGoal.bestPaceAtDistance ||
    _goal == ChallengeGoal.collectiveDistance;


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
        target = raw * 1000; // km → meters
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
      goal: _goal,
      target: target,
      windowMs: windowMs,
      startMode: startMode,
      fixedStartMs: fixedStartMs,
      entryFeeCoins: fee,
      acceptWindowMin: (_type == ChallengeType.group || _type == ChallengeType.team) && _mode == 0
          ? _acceptWindowMin
          : null,
      maxParticipants:
          _type != ChallengeType.oneVsOne ? _maxParticipants : null,
    );

    final typeStr = switch (_type) {
      ChallengeType.oneVsOne => 'one_vs_one',
      ChallengeType.group => 'group',
      ChallengeType.team => 'team',
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

// ═══════════════════════════════════════════════════════════════════════════
// Goal card
// ═══════════════════════════════════════════════════════════════════════════

class _GoalCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _GoalCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    return Material(
      color: selected ? cs.primaryContainer : cs.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? cs.primary : Colors.transparent,
              width: 2,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, size: 28,
                  color: selected ? cs.primary : cs.outline),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: selected ? cs.primary : null,
                        )),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: cs.outline, fontSize: 11)),
                  ],
                ),
              ),
              if (selected)
                Icon(Icons.check_circle, size: 22, color: cs.primary),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Mode card
// ═══════════════════════════════════════════════════════════════════════════

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

class _TypeInfoBox extends StatelessWidget {
  final ChallengeType type;
  const _TypeInfoBox({required this.type});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    final (icon, text) = switch (type) {
      ChallengeType.oneVsOne => (
        Icons.people,
        'Duelo direto entre 2 corredores. '
        'Quem tiver o melhor resultado ganha.',
      ),
      ChallengeType.group => (
        Icons.groups,
        'Cada corredor compete individualmente. '
        'Ranking por desempenho — o 1.o lugar leva o prêmio todo.',
      ),
      ChallengeType.team => (
        Icons.shield_rounded,
        'Time A vs Time B. Você escolhe quem vai para cada time. '
        'Os times devem ter o mesmo número de atletas. '
        'O time vencedor divide o prêmio.',
      ),
    };

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cs.tertiaryContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: cs.tertiary),
          const SizedBox(width: 8),
          Expanded(child: Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onTertiaryContainer),
          )),
        ],
      ),
    );
  }
}

class _WinnerExplainerBox extends StatelessWidget {
  final ChallengeGoal goal;
  final ChallengeType type;
  const _WinnerExplainerBox({required this.goal, required this.type});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    final explanation = _explain();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.secondaryContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.secondaryContainer),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.emoji_events_rounded, size: 16, color: cs.secondary),
              const SizedBox(width: 6),
              Text('Como o vencedor é decidido',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: cs.secondary,
                )),
            ],
          ),
          const SizedBox(height: 6),
          Text(explanation,
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSecondaryContainer,
              height: 1.4,
            )),
        ],
      ),
    );
  }

  String _explain() {
    if (type == ChallengeType.team) {
      return switch (goal) {
        ChallengeGoal.fastestAtDistance =>
          'Cada membro do time corre a distância. '
          'O tempo do time = tempo do ÚLTIMO membro a completar (todos precisam correr). '
          'Ganha o time que completar mais rápido.',
        ChallengeGoal.mostDistance =>
          'Cada membro corre o que puder. '
          'Km do time = soma dos km de TODOS os membros. '
          'Ganha o time com mais km totais.',
        ChallengeGoal.bestPaceAtDistance =>
          'Cada membro corre a distância mínima. '
          'Pace do time = média dos paces de TODOS os membros. '
          'Ganha o time com o menor pace médio.',
        ChallengeGoal.collectiveDistance =>
          'Cada membro do time corre o que puder — os km de todos somam. '
          'O time que acumular mais km no total vence e leva os coins do outro time.',
      };
    }
    if (goal == ChallengeGoal.collectiveDistance) {
      return 'Cooperativo por time: cada membro corre o que puder e os km de '
          'todos no time somam. O time que acumular mais km totais vence e '
          'leva os OmniCoins do time adversário.';
    }
    return switch (goal) {
      ChallengeGoal.fastestAtDistance =>
        'Cada corredor faz uma corrida cobrindo a distância definida. '
        'Ganha quem completar no menor tempo. '
        'Exemplo: distância = 10 km → ganha quem correr 10 km mais rápido.',
      ChallengeGoal.mostDistance =>
        'Cada corredor pode fazer quantas corridas quiser dentro do prazo. '
        'Todas as corridas somam. Ganha quem acumular mais km no total. '
        'Exemplo: prazo = 7 dias → ganha quem somar mais km em 7 dias.',
      ChallengeGoal.bestPaceAtDistance =>
        'Cada corredor faz uma corrida que cubra pelo menos a distância mínima. '
        'Ganha quem tiver o menor pace médio (min/km) nessa corrida. '
        'Exemplo: distância = 5 km → ganha quem correr 5+ km com melhor pace.',
      ChallengeGoal.collectiveDistance =>
        'Cooperativo por time: cada membro corre o que puder e os km de '
        'todos somam. O time com mais km vence e leva os coins do outro.',
    };
  }
}
