import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/core/utils/error_messages.dart';
import 'package:omni_runner/core/service_locator.dart';
import 'package:omni_runner/core/theme/design_tokens.dart';
import 'package:omni_runner/domain/usecases/wearable/import_execution.dart';

class AthleteLogExecutionScreen extends StatefulWidget {
  final String? assignmentId;
  final String? assignmentLabel;

  const AthleteLogExecutionScreen({
    super.key,
    this.assignmentId,
    this.assignmentLabel,
  });

  @override
  State<AthleteLogExecutionScreen> createState() =>
      _AthleteLogExecutionScreenState();
}

class _AthleteLogExecutionScreenState extends State<AthleteLogExecutionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _importExecution = sl<ImportExecution>();

  final _durationCtrl = TextEditingController();
  final _distanceCtrl = TextEditingController();
  final _paceCtrl = TextEditingController();
  final _hrCtrl = TextEditingController();

  String _source = 'manual';
  bool _submitting = false;

  static const _sourceOptions = ['manual', 'garmin', 'apple', 'polar', 'suunto'];
  static const _sourceLabels = {
    'manual': 'Manual',
    'garmin': 'Garmin',
    'apple': 'Apple Watch',
    'polar': 'Polar',
    'suunto': 'Suunto',
  };

  @override
  void dispose() {
    _durationCtrl.dispose();
    _distanceCtrl.dispose();
    _paceCtrl.dispose();
    _hrCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _submitting = true);
    try {
      final durationMinutes = int.tryParse(_durationCtrl.text.trim()) ?? 0;
      await _importExecution.call(
        assignmentId: widget.assignmentId,
        durationSeconds: durationMinutes * 60,
        distanceMeters: _distanceCtrl.text.trim().isNotEmpty
            ? int.tryParse(_distanceCtrl.text.trim())
            : null,
        avgPace: _paceCtrl.text.trim().isNotEmpty
            ? int.tryParse(_paceCtrl.text.trim())
            : null,
        avgHr: _hrCtrl.text.trim().isNotEmpty
            ? int.tryParse(_hrCtrl.text.trim())
            : null,
        source: _source,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Execução registrada com sucesso!')),
      );
      context.pop(true);
    } on Object catch (e, st) {
      AppLogger.error('LogExecution submit failed', error: e, stack: st);
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ErrorMessages.humanize(e)),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Semantics(
      label: 'Tela de Registrar Execução',
      child: Scaffold(
      appBar: AppBar(title: const Text('Registrar Execução')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.assignmentLabel != null) ...[
                Card(
                  color: theme.colorScheme.primaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(DesignTokens.spacingMd),
                    child: Row(
                      children: [
                        Icon(Icons.fitness_center,
                            color: theme.colorScheme.onPrimaryContainer),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            widget.assignmentLabel!,
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: theme.colorScheme.onPrimaryContainer,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],

              TextFormField(
                controller: _durationCtrl,
                decoration: const InputDecoration(
                  labelText: 'Duração (minutos) *',
                  prefixIcon: Icon(Icons.timer),
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'Duração é obrigatória';
                  }
                  final val = int.tryParse(v.trim());
                  if (val == null || val <= 0) {
                    return 'Valor inválido';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _distanceCtrl,
                decoration: const InputDecoration(
                  labelText: 'Distância (metros)',
                  prefixIcon: Icon(Icons.straighten),
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _paceCtrl,
                decoration: const InputDecoration(
                  labelText: 'Pace médio (seg/km)',
                  prefixIcon: Icon(Icons.speed),
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _hrCtrl,
                decoration: const InputDecoration(
                  labelText: 'FC média (bpm)',
                  prefixIcon: Icon(Icons.monitor_heart),
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              ),
              const SizedBox(height: 16),

              DropdownButtonFormField<String>(
                initialValue: _source,
                decoration: const InputDecoration(
                  labelText: 'Fonte',
                  prefixIcon: Icon(Icons.devices),
                  border: OutlineInputBorder(),
                ),
                items: _sourceOptions
                    .map((s) => DropdownMenuItem(
                          value: s,
                          child: Text(_sourceLabels[s] ?? s),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _source = v);
                },
              ),
              const SizedBox(height: 32),

              FilledButton.icon(
                onPressed: _submitting ? null : _submit,
                icon: _submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check),
                label: Text(_submitting ? 'Enviando...' : 'Registrar'),
              ),
            ],
          ),
        ),
      ),
    ),
    );
  }
}
