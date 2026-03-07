import 'package:flutter/material.dart';

/// Instruction screen — "Como importar no Garmin/Outros".
///
/// All text comes directly from `docs/PHASE_14_INTEGRATIONS.md` §11.2–11.3.
/// No invented copy — only what was documented and approved.
class HowToImportScreen extends StatelessWidget {
  const HowToImportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Como importar'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Garmin Connect (Web) ───────────────────────
          const _SectionHeader(title: 'Garmin Connect (Web)'),
          const SizedBox(height: 8),
          const _StepTile(number: '1', text: 'No Omni Runner, toque Exportar e '
              'escolha FIT (ou GPX).'),
          const _StepTile(number: '2', text: 'Na share sheet, escolha '
              '"Salvar em Arquivos" (iOS) ou "Downloads" (Android).'),
          const _StepTile(number: '3', text: 'Abra connect.garmin.com '
              'no navegador.'),
          const _StepTile(number: '4', text: 'Menu lateral \u2192 '
              'Importar Dados \u2192 arraste o arquivo .fit / .gpx.'),
          const _StepTile(number: '5', text: 'Garmin processa e a atividade '
              'aparece no histórico.'),

          const SizedBox(height: 20),

          // ── Garmin Connect (App Mobile) ────────────────
          const _SectionHeader(title: 'Garmin Connect (App Mobile)'),
          const SizedBox(height: 8),
          const _StepTile(number: '1', text: 'No Omni Runner, exporte como FIT '
              'e compartilhe via share sheet.'),
          const _StepTile(number: '2', text: 'Escolha "Garmin Connect" na '
              'lista de apps \u2014 ou use "Abrir com" \u2192 Garmin Connect.'),
          const _StepTile(number: '3', text: 'O app da Garmin importa '
              'automaticamente ao receber o arquivo.'),
          Padding(
            padding: const EdgeInsets.only(left: 12, top: 8),
            child: Text(
              'A opção "Abrir com Garmin Connect" depende do dispositivo '
              'e versão do app. Se não aparecer, use o método via web.',
              style: TextStyle(
                fontSize: 12,
                fontStyle: FontStyle.italic,
                color: Colors.grey.shade600,
              ),
            ),
          ),

          const SizedBox(height: 20),

          // ── Outras plataformas ─────────────────────────
          const _SectionHeader(title: 'Outras plataformas'),
          const SizedBox(height: 8),
          const _PlatformRow(
            platform: 'Coros',
            format: 'FIT',
            instruction: 'coros.com \u2192 Histórico \u2192 Importar Arquivo',
          ),
          const _PlatformRow(
            platform: 'Suunto',
            format: 'GPX / FIT',
            instruction: 'suuntoapp.com \u2192 arrastar arquivo',
          ),
          const _PlatformRow(
            platform: 'TrainingPeaks',
            format: 'FIT',
            instruction: 'trainingpeaks.com \u2192 Adicionar Treino '
                '\u2192 Importar Arquivo',
          ),
          const _PlatformRow(
            platform: 'intervals.icu',
            format: 'FIT / GPX',
            instruction: 'intervals.icu \u2192 Activities \u2192 Upload',
          ),
          const _PlatformRow(
            platform: 'Runalyze',
            format: 'FIT / GPX / TCX',
            instruction: 'runalyze.com \u2192 Importar \u2192 arrastar arquivo',
          ),
          const _PlatformRow(
            platform: 'Smashrun',
            format: 'GPX / TCX',
            instruction: 'smashrun.com \u2192 Import \u2192 selecionar arquivo',
          ),

          const SizedBox(height: 24),

          // ── Limitações ─────────────────────────────────
          const _SectionHeader(title: 'Bom saber'),
          const SizedBox(height: 8),
          const _InfoTile(
            icon: Icons.star_outline,
            text: 'FIT é o formato mais completo: HR, pace, calorias, '
                'info do dispositivo. Se a plataforma aceitar FIT, prefira.',
          ),
          const _InfoTile(
            icon: Icons.favorite_border,
            text: 'HR pode não aparecer em todas as plataformas quando '
                'exportado em GPX. FIT é mais confiável para dados de '
                'frequência cardíaca.',
          ),
          const _InfoTile(
            icon: Icons.route,
            text: 'Dados de lap/split não existem em GPX (trilha contínua). '
                'Splits aparecem em TCX e FIT.',
          ),
          const _InfoTile(
            icon: Icons.info_outline,
            text: 'Garmin, Coros e Suunto não oferecem API pública de upload. '
                'A importação por arquivo é o padrão da indústria.',
          ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

// ── Private widgets ──────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.bold,
          ),
    );
  }
}

class _StepTile extends StatelessWidget {
  final String number;
  final String text;
  const _StepTile({required this.number, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            child: Text(
              number,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 14)),
          ),
        ],
      ),
    );
  }
}

class _PlatformRow extends StatelessWidget {
  final String platform;
  final String format;
  final String instruction;

  const _PlatformRow({
    required this.platform,
    required this.format,
    required this.instruction,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  platform,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                Text(
                  format,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              instruction,
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoTile({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: Colors.grey.shade700),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
            ),
          ),
        ],
      ),
    );
  }
}
