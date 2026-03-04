import 'package:flutter/material.dart';
import 'package:omni_runner/core/logging/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:omni_runner/core/errors/integrations_failures.dart';
import 'package:omni_runner/core/service_locator.dart';
import 'package:omni_runner/core/storage/preferences_keys.dart';
import 'package:omni_runner/domain/entities/workout_session_entity.dart';
import 'package:omni_runner/features/integrations_export/domain/export_format.dart';
import 'package:omni_runner/features/integrations_export/presentation/export_sheet_controller.dart';
import 'package:omni_runner/features/integrations_export/presentation/how_to_import_screen.dart';
import 'package:omni_runner/features/integrations_export/presentation/share_export_file.dart';
import 'package:omni_runner/presentation/screens/settings_screen.dart';


/// Export screen — lets the user choose a format and share the file.
///
/// Matches the UX spec from `docs/PHASE_14_INTEGRATIONS.md` §11.4 Tela 1.
/// After sharing, shows a post-export bottom sheet (Tela 2) and
/// optionally a Strava education sheet on first use (Tela 3).
class ExportScreen extends StatefulWidget {
  final WorkoutSessionEntity session;

  const ExportScreen({super.key, required this.session});

  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends State<ExportScreen> {
  ExportFormat _selected = ExportFormat.gpx;
  bool _exporting = false;

  Future<void> _export() async {
    setState(() => _exporting = true);

    try {
      final controller = sl<ExportSheetController>();
      final result = await controller.export(
        session: widget.session,
        format: _selected,
      );

      await shareExportFile(result);

      if (!mounted) return;

      await _showPostExportSheet(result.format);
      await _maybeShowStravaEducation();
    } on IntegrationFailure catch (e) {
      AppLogger.warn('Export failed: $e', tag: 'ExportScreen');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha ao exportar: $e')),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  /// Tela 2 — post-export instruction bottom sheet.
  Future<void> _showPostExportSheet(ExportFormat format) async {
    final ext = format.extension;

    await showModalBottomSheet<void>(
      context: context,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.check_circle,
                      color: Colors.green.shade600, size: 28),
                  const SizedBox(width: 8),
                  Text(
                    'Arquivo salvo!',
                    style: Theme.of(_contextOrFallback)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                'Para importar no Garmin Connect:',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              const Text('1. Abra connect.garmin.com'),
              const Text('2. Vá em Importar Dados'),
              Text('3. Arraste o arquivo $ext'),  // $ext is runtime
              const SizedBox(height: 12),
              Text(
                'Ou abra o arquivo direto no app\n'
                'Garmin Connect do seu celular.',
                style: TextStyle(color: Colors.grey.shade600),
              ),
              const SizedBox(height: 12),
              const Divider(),
              Text(
                'Coros, Suunto, TrainingPeaks:\n'
                'mesmo processo no site oficial.',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(_contextOrFallback).pop(),
                  child: const Text('Entendi'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  BuildContext get _contextOrFallback => context;

  /// Tela 3 — first-use Strava education sheet.
  Future<void> _maybeShowStravaEducation() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(PreferencesKeys.hasSeenGarminImportGuide) == true) return;

    await prefs.setBool(PreferencesKeys.hasSeenGarminImportGuide, true);

    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Sabia que\u2026',
                style: Theme.of(_contextOrFallback)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              const Text(
                'O Strava recebe corridas automaticamente! '
                'Conecte sua conta em Configurações \u2192 Strava.',
              ),
              const SizedBox(height: 8),
              const Text(
                'Para Garmin e outros, a importação é por arquivo '
                '\u2014 é o padrão da indústria.',
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () =>
                          Navigator.of(_contextOrFallback).pop(),
                      child: const Text('Pular'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () {
                        Navigator.of(_contextOrFallback).pop();
                        Navigator.of(context).push(MaterialPageRoute<void>(
                          builder: (_) => const SettingsScreen(),
                        ));
                      },
                      child: const Text('Conectar Strava'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Exportar Corrida'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            tooltip: 'Como importar',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const HowToImportScreen(),
              ),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Escolha o formato:',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 12),
            _FormatCard(
              format: ExportFormat.gpx,
              title: 'GPX',
              subtitle: 'Universal: rota + HR.\nFunciona em qualquer app.',
              selected: _selected == ExportFormat.gpx,
              onTap: () => setState(() => _selected = ExportFormat.gpx),
            ),
            const SizedBox(height: 8),
            _FormatCard(
              format: ExportFormat.tcx,
              title: 'TCX',
              subtitle: 'Garmin Connect,\nTrainingPeaks, Strava.',
              selected: _selected == ExportFormat.tcx,
              onTap: () => setState(() => _selected = ExportFormat.tcx),
            ),
            const SizedBox(height: 8),
            _FormatCard(
              format: ExportFormat.fit,
              title: 'FIT',
              subtitle: 'Mais completo: HR, pace,\ncalorias. Garmin, Coros, '
                  'TrainingPeaks.',
              selected: _selected == ExportFormat.fit,
              onTap: () => setState(() => _selected = ExportFormat.fit),
            ),
            const Spacer(),
            FilledButton.icon(
              onPressed: _exporting ? null : _export,
              icon: _exporting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.share),
              label: Text(_exporting ? 'Exportando\u2026' : 'Exportar'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Selectable card for a single export format.
class _FormatCard extends StatelessWidget {
  final ExportFormat format;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _FormatCard({
    required this.format,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final borderColor =
        selected ? colorScheme.primary : colorScheme.outlineVariant;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor, width: selected ? 2 : 1),
          color: selected
              ? colorScheme.primaryContainer.withAlpha(60)
              : Colors.transparent,
        ),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              color: selected
                  ? colorScheme.primary
                  : colorScheme.onSurfaceVariant,
              size: 22,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
