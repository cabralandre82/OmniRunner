import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:omni_runner/domain/entities/token_intent_entity.dart';
import 'package:omni_runner/presentation/blocs/staff_qr/staff_qr_bloc.dart';
import 'package:omni_runner/presentation/blocs/staff_qr/staff_qr_event.dart';
import 'package:omni_runner/presentation/blocs/staff_qr/staff_qr_state.dart';

/// Displays a generated QR code for a token intent with a countdown timer.
///
/// Staff selects amount and generates. The QR auto-expires after the server-set TTL.
class StaffGenerateQrScreen extends StatefulWidget {
  final TokenIntentType type;
  final String groupId;
  final String? championshipId;

  const StaffGenerateQrScreen({
    super.key,
    required this.type,
    required this.groupId,
    this.championshipId,
  });

  @override
  State<StaffGenerateQrScreen> createState() => _StaffGenerateQrScreenState();
}

class _StaffGenerateQrScreenState extends State<StaffGenerateQrScreen> {
  int _amount = 1;
  Timer? _countdownTimer;
  Duration _remaining = Duration.zero;

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _startCountdown(StaffQrPayload payload) {
    _countdownTimer?.cancel();
    _remaining = payload.remainingDuration;
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final r = payload.remainingDuration;
      if (!mounted) return;
      setState(() => _remaining = r);
      if (r <= Duration.zero) _countdownTimer?.cancel();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(tokenIntentLabel(widget.type))),
      body: BlocConsumer<StaffQrBloc, StaffQrState>(
        listener: (context, state) {
          if (state is StaffQrGenerated) _startCountdown(state.payload);
          if (state is StaffQrError) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.message),
                backgroundColor: theme.colorScheme.error,
              ),
            );
          }
        },
        builder: (context, state) => switch (state) {
          StaffQrInitial() => _buildForm(context, theme),
          StaffQrGenerating() =>
            const Center(child: CircularProgressIndicator()),
          StaffQrGenerated(:final payload) =>
            _buildQrDisplay(context, theme, payload),
          StaffQrError() => _buildForm(context, theme),
          _ => const SizedBox.shrink(),
        },
      ),
    );
  }

  Widget _buildForm(BuildContext context, ThemeData theme) {
    final isBadge = widget.type == TokenIntentType.champBadgeActivate;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(
            _iconForType(widget.type),
            size: 64,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text(
            tokenIntentLabel(widget.type),
            style: theme.textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            _descriptionForType(widget.type),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          if (!isBadge) ...[
            Text('Quantidade', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Row(
              children: [
                IconButton.outlined(
                  onPressed: _amount > 1
                      ? () => setState(() => _amount--)
                      : null,
                  icon: const Icon(Icons.remove),
                ),
                Expanded(
                  child: Text(
                    '$_amount',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineMedium,
                  ),
                ),
                IconButton.outlined(
                  onPressed: () => setState(() => _amount++),
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            const SizedBox(height: 32),
          ],
          FilledButton.icon(
            onPressed: () => context.read<StaffQrBloc>().add(
                  GenerateQr(
                    type: widget.type,
                    groupId: widget.groupId,
                    amount: isBadge ? 1 : _amount,
                    championshipId: widget.championshipId,
                  ),
                ),
            icon: const Icon(Icons.qr_code),
            label: const Text('Gerar QR'),
          ),
        ],
      ),
    );
  }

  Widget _buildQrDisplay(
    BuildContext context,
    ThemeData theme,
    StaffQrPayload payload,
  ) {
    final expired = _remaining <= Duration.zero;
    final minutes = _remaining.inMinutes;
    final seconds = _remaining.inSeconds % 60;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Text(
            tokenIntentLabel(widget.type),
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: expired
                  ? theme.colorScheme.errorContainer
                  : Colors.green.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  expired ? Icons.timer_off : Icons.timer,
                  size: 18,
                  color: expired ? theme.colorScheme.error : Colors.green,
                ),
                const SizedBox(width: 6),
                Text(
                  expired
                      ? 'Expirado'
                      : 'Expira em ${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: expired ? theme.colorScheme.error : Colors.green,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          if (!expired)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: QrImageView(
                data: payload.encode(),
                version: QrVersions.auto,
                size: 250,
                gapless: true,
              ),
            )
          else
            Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.timer_off,
                        size: 48, color: theme.colorScheme.error),
                    const SizedBox(height: 8),
                    Text('QR Expirado',
                        style:
                            TextStyle(color: theme.colorScheme.error)),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 16),
          Text(
            'Quantidade: ${payload.amount}',
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: () =>
                context.read<StaffQrBloc>().add(const ResetStaffQr()),
            icon: const Icon(Icons.refresh),
            label: const Text('Gerar Novo'),
          ),
        ],
      ),
    );
  }

  static IconData _iconForType(TokenIntentType t) => switch (t) {
        TokenIntentType.issueToAthlete => Icons.card_giftcard,
        TokenIntentType.burnFromAthlete => Icons.local_fire_department,
        TokenIntentType.champBadgeActivate => Icons.military_tech,
      };

  static String _descriptionForType(TokenIntentType t) => switch (t) {
        TokenIntentType.issueToAthlete =>
          'Gere um QR para o atleta escanear e receber OmniCoins.',
        TokenIntentType.burnFromAthlete =>
          'Gere um QR para o atleta escanear e devolver OmniCoins.',
        TokenIntentType.champBadgeActivate =>
          'Gere um QR para ativar o badge temporário de campeonato.',
      };
}
