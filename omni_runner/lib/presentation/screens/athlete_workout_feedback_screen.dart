import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:omni_runner/core/service_locator.dart';
import 'package:omni_runner/core/theme/design_tokens.dart';
import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/domain/entities/plan_workout_entity.dart';
import 'package:omni_runner/domain/repositories/i_training_plan_repo.dart';

/// Tela de conclusão e feedback pós-treino.
///
/// Recebe o [releaseId] e opcionalmente a [workout] para pré-preencher dados.
/// Ao confirmar, chama completeWorkout() + submitFeedback() e retorna true
/// para que a tela anterior saiba que houve atualização.
class AthleteWorkoutFeedbackScreen extends StatefulWidget {
  const AthleteWorkoutFeedbackScreen({
    super.key,
    required this.releaseId,
    this.workout,
  });

  final String releaseId;
  final PlanWorkoutEntity? workout;

  @override
  State<AthleteWorkoutFeedbackScreen> createState() =>
      _AthleteWorkoutFeedbackScreenState();
}

class _AthleteWorkoutFeedbackScreenState
    extends State<AthleteWorkoutFeedbackScreen> {
  final _formKey = GlobalKey<FormState>();

  // Execution fields
  final _distanceCtrl = TextEditingController();
  final _minutesCtrl = TextEditingController();
  final _secondsCtrl = TextEditingController();

  // Feedback fields
  int _rating = 0;
  int _mood = 3;
  int _rpe = 5;
  final _howWasItCtrl = TextEditingController();
  final _whatWasHardCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  bool _submitting = false;
  static const _tag = 'WorkoutFeedbackScreen';

  @override
  void initState() {
    super.initState();
    // Pre-fill if re-editing existing feedback
    final fb = widget.workout?.feedback;
    if (fb != null) {
      _rating = fb.rating ?? 0;
      _mood = fb.mood ?? 3;
      if (fb.howWasIt != null) _howWasItCtrl.text = fb.howWasIt!;
    }
    final comp = widget.workout?.completedWorkout;
    if (comp != null) {
      if (comp.actualDistanceM != null) {
        _distanceCtrl.text =
            (comp.actualDistanceM! / 1000).toStringAsFixed(2);
      }
      if (comp.actualDurationS != null) {
        _minutesCtrl.text = (comp.actualDurationS! ~/ 60).toString();
        _secondsCtrl.text = (comp.actualDurationS! % 60)
            .toString()
            .padLeft(2, '0');
      }
      if (comp.perceivedEffort != null) _rpe = comp.perceivedEffort!;
    }
  }

  @override
  void dispose() {
    _distanceCtrl.dispose();
    _minutesCtrl.dispose();
    _secondsCtrl.dispose();
    _howWasItCtrl.dispose();
    _whatWasHardCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  double? _parseDistance() {
    final text = _distanceCtrl.text.trim().replaceAll(',', '.');
    if (text.isEmpty) return null;
    final km = double.tryParse(text);
    return km != null ? km * 1000 : null;
  }

  int? _parseDurationSeconds() {
    final min = int.tryParse(_minutesCtrl.text.trim()) ?? 0;
    final sec = int.tryParse(_secondsCtrl.text.trim()) ?? 0;
    if (min == 0 && sec == 0) return null;
    return min * 60 + sec;
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? true)) return;
    if (_submitting) return;

    HapticFeedback.mediumImpact();
    setState(() => _submitting = true);

    try {
      final repo = sl<ITrainingPlanRepo>();

      final distanceM = _parseDistance();
      final durationS = _parseDurationSeconds();

      await repo.completeWorkout(
        releaseId: widget.releaseId,
        actualDistanceM: distanceM,
        actualDurationS: durationS,
        perceivedEffort: _rpe,
        mood: _mood,
        source: 'manual',
      );

      final hasTextFeedback = _howWasItCtrl.text.trim().isNotEmpty ||
          _whatWasHardCtrl.text.trim().isNotEmpty ||
          _notesCtrl.text.trim().isNotEmpty;

      if (_rating > 0 || hasTextFeedback) {
        await repo.submitFeedback(
          releaseId: widget.releaseId,
          rating: _rating > 0 ? _rating : null,
          perceivedEffort: _rpe,
          mood: _mood,
          howWasIt: _howWasItCtrl.text.trim().isNotEmpty
              ? _howWasItCtrl.text.trim()
              : null,
          whatWasHard: _whatWasHardCtrl.text.trim().isNotEmpty
              ? _whatWasHardCtrl.text.trim()
              : null,
          notes: _notesCtrl.text.trim().isNotEmpty
              ? _notesCtrl.text.trim()
              : null,
        );
      }

      if (mounted) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: DesignTokens.success),
                SizedBox(width: 8),
                Text('Treino concluído!'),
              ],
            ),
            duration: Duration(seconds: 3),
          ),
        );
      }
    } on Object catch (e) {
      AppLogger.error('submitFeedback failed', tag: _tag, error: e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Erro ao salvar. Tente novamente.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final workoutName = widget.workout?.displayName ?? 'Treino';

    return Scaffold(
      appBar: AppBar(
        title: Text('Concluir: $workoutName', overflow: TextOverflow.ellipsis),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            DesignTokens.spacingMd,
            DesignTokens.spacingMd,
            DesignTokens.spacingMd,
            120,
          ),
          children: [
            // ── Execution section ──────────────────────────────────────────
            const _SectionHeader(
              icon: Icons.directions_run,
              title: 'O que você fez',
              subtitle: 'Opcional — informe os dados da sua execução',
            ),
            const SizedBox(height: DesignTokens.spacingMd),
            Row(
              children: [
                Expanded(
                  child: _InputCard(
                    label: 'Distância (km)',
                    child: TextFormField(
                      controller: _distanceCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                            RegExp(r'[0-9.,]')),
                      ],
                      decoration: const InputDecoration(
                        hintText: 'ex: 5.2',
                        border: InputBorder.none,
                        suffixText: 'km',
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: DesignTokens.spacingSm),
                Expanded(
                  child: _InputCard(
                    label: 'Duração',
                    child: Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _minutesCtrl,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            decoration: const InputDecoration(
                              hintText: '00',
                              border: InputBorder.none,
                              suffixText: 'min',
                            ),
                          ),
                        ),
                        const Text(':'),
                        Expanded(
                          child: TextFormField(
                            controller: _secondsCtrl,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(2),
                            ],
                            decoration: const InputDecoration(
                              hintText: '00',
                              border: InputBorder.none,
                              suffixText: 's',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: DesignTokens.spacingLg),

            // ── Effort ────────────────────────────────────────────────────
            const _SectionHeader(
              icon: Icons.bar_chart,
              title: 'Esforço percebido (RPE)',
              subtitle: 'Como foi a intensidade do treino?',
            ),
            const SizedBox(height: DesignTokens.spacingMd),
            _RpeSelector(
              value: _rpe,
              onChanged: (v) => setState(() => _rpe = v),
            ),

            const SizedBox(height: DesignTokens.spacingLg),

            // ── Mood ──────────────────────────────────────────────────────
            const _SectionHeader(
              icon: Icons.mood,
              title: 'Como você se sentiu?',
              subtitle: 'Seu estado físico e mental',
            ),
            const SizedBox(height: DesignTokens.spacingMd),
            _MoodSelector(
              value: _mood,
              onChanged: (v) => setState(() => _mood = v),
            ),

            const SizedBox(height: DesignTokens.spacingLg),

            // ── Rating ────────────────────────────────────────────────────
            const _SectionHeader(
              icon: Icons.star_outline,
              title: 'Avalie o treino',
              subtitle: 'Opcional',
            ),
            const SizedBox(height: DesignTokens.spacingMd),
            _StarRating(
              value: _rating,
              onChanged: (v) => setState(() => _rating = v),
            ),

            const SizedBox(height: DesignTokens.spacingLg),

            // ── Text fields ───────────────────────────────────────────────
            const _SectionHeader(
              icon: Icons.comment_outlined,
              title: 'Comentários',
              subtitle: 'Opcional',
            ),
            const SizedBox(height: DesignTokens.spacingMd),
            _TextCard(
              label: 'Como foi o treino?',
              controller: _howWasItCtrl,
              hint: 'ex: Foi bem! Mantive o ritmo no intervalo...',
              maxLines: 3,
            ),
            const SizedBox(height: DesignTokens.spacingSm),
            _TextCard(
              label: 'O que foi difícil?',
              controller: _whatWasHardCtrl,
              hint: 'ex: Os últimos 2 tiros foram bem puxados...',
              maxLines: 2,
            ),
            const SizedBox(height: DesignTokens.spacingSm),
            _TextCard(
              label: 'Observações adicionais',
              controller: _notesCtrl,
              hint: 'Qualquer outra nota para o treinador...',
              maxLines: 2,
            ),
          ],
        ),
      ),
      bottomNavigationBar: _SubmitBar(
        submitting: _submitting,
        onSubmit: _submit,
      ),
    );
  }
}

// ─── Section Header ───────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: DesignTokens.brand.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
          ),
          child: Icon(icon, size: 16, color: DesignTokens.brand),
        ),
        const SizedBox(width: DesignTokens.spacingSm),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: DesignTokens.textPrimary,
              ),
            ),
            Text(
              subtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: DesignTokens.textMuted,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ─── Input Card ───────────────────────────────────────────────────────────────

class _InputCard extends StatelessWidget {
  const _InputCard({required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignTokens.spacingMd,
        vertical: DesignTokens.spacingSm,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? DesignTokens.surface
            : Colors.white,
        borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
        border: Border.all(color: DesignTokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: DesignTokens.textMuted,
                ),
          ),
          child,
        ],
      ),
    );
  }
}

// ─── RPE Selector ─────────────────────────────────────────────────────────────

class _RpeSelector extends StatelessWidget {
  const _RpeSelector({required this.value, required this.onChanged});
  final int value;
  final ValueChanged<int> onChanged;

  static const _labels = <int, String>{
    1: 'Muito leve',
    2: 'Leve',
    3: 'Moderado',
    4: 'Um pouco difícil',
    5: 'Difícil',
    6: 'Mais difícil',
    7: 'Muito difícil',
    8: 'Intenso',
    9: 'Muito intenso',
    10: 'Máximo',
  };

  Color _rpeColor(int v) {
    if (v <= 3) return DesignTokens.success;
    if (v <= 5) return DesignTokens.warning;
    if (v <= 7) return const Color(0xFFFF8C00);
    return DesignTokens.error;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(10, (i) {
            final v = i + 1;
            final selected = v == value;
            final color = _rpeColor(v);
            return GestureDetector(
              onTap: () => onChanged(v),
              child: AnimatedContainer(
                duration: DesignTokens.durationFast,
                width: 28,
                height: 36,
                decoration: BoxDecoration(
                  color: selected
                      ? color
                      : color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
                  border: Border.all(
                    color: selected ? color : color.withValues(alpha: 0.3),
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  '$v',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: selected ? Colors.white : color,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: DesignTokens.spacingXs),
        Text(
          _labels[value] ?? '',
          style: theme.textTheme.bodySmall?.copyWith(
            color: _rpeColor(value),
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

// ─── Mood Selector ────────────────────────────────────────────────────────────

class _MoodSelector extends StatelessWidget {
  const _MoodSelector({required this.value, required this.onChanged});
  final int value;
  final ValueChanged<int> onChanged;

  static const _emojis = ['😩', '😕', '😐', '🙂', '😄'];
  static const _labels = ['Péssimo', 'Ruim', 'Neutro', 'Bom', 'Ótimo'];

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: List.generate(5, (i) {
        final v = i + 1;
        final selected = v == value;
        return GestureDetector(
          onTap: () => onChanged(v),
          child: AnimatedContainer(
            duration: DesignTokens.durationFast,
            width: 60,
            height: 72,
            decoration: BoxDecoration(
              color: selected
                  ? DesignTokens.brand.withValues(alpha: 0.12)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
              border: Border.all(
                color: selected
                    ? DesignTokens.brand
                    : DesignTokens.border,
                width: selected ? 2 : 1,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _emojis[i],
                  style: TextStyle(fontSize: selected ? 28 : 24),
                ),
                Text(
                  _labels[i],
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: selected
                            ? DesignTokens.brand
                            : DesignTokens.textMuted,
                        fontWeight: selected ? FontWeight.w600 : null,
                      ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}

// ─── Star Rating ──────────────────────────────────────────────────────────────

class _StarRating extends StatelessWidget {
  const _StarRating({required this.value, required this.onChanged});
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(5, (i) {
        final v = i + 1;
        return GestureDetector(
          onTap: () => onChanged(v == value ? 0 : v),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Icon(
              v <= value ? Icons.star_rounded : Icons.star_border_rounded,
              size: 40,
              color: v <= value
                  ? DesignTokens.warning
                  : DesignTokens.textMuted,
            ),
          ),
        );
      }),
    );
  }
}

// ─── Text Card ────────────────────────────────────────────────────────────────

class _TextCard extends StatelessWidget {
  const _TextCard({
    required this.label,
    required this.controller,
    required this.hint,
    this.maxLines = 2,
  });

  final String label;
  final TextEditingController controller;
  final String hint;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignTokens.spacingMd,
        vertical: DesignTokens.spacingSm,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? DesignTokens.surface
            : Colors.white,
        borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
        border: Border.all(color: DesignTokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: DesignTokens.textMuted,
                ),
          ),
          TextFormField(
            controller: controller,
            maxLines: maxLines,
            decoration: InputDecoration(
              hintText: hint,
              border: InputBorder.none,
              isDense: true,
              contentPadding:
                  const EdgeInsets.only(top: DesignTokens.spacingXs),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Submit Bar ───────────────────────────────────────────────────────────────

class _SubmitBar extends StatelessWidget {
  const _SubmitBar({required this.submitting, required this.onSubmit});
  final bool submitting;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        DesignTokens.spacingMd,
        DesignTokens.spacingSm,
        DesignTokens.spacingMd,
        DesignTokens.spacingLg,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? DesignTokens.bgSecondary
            : Colors.white,
        border: const Border(top: BorderSide(color: DesignTokens.border)),
      ),
      child: FilledButton.icon(
        onPressed: submitting ? null : onSubmit,
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          backgroundColor: DesignTokens.success,
        ),
        icon: submitting
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.check_circle_outline),
        label: Text(submitting ? 'Salvando...' : 'Salvar e concluir'),
      ),
    );
  }
}
