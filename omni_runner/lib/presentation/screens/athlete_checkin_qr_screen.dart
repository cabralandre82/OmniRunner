import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:omni_runner/core/service_locator.dart';
import 'package:omni_runner/core/theme/design_tokens.dart';
import 'package:omni_runner/domain/repositories/i_training_attendance_repo.dart';
import 'package:omni_runner/presentation/blocs/checkin/checkin_bloc.dart';
import 'package:omni_runner/presentation/blocs/checkin/checkin_event.dart';
import 'package:omni_runner/presentation/blocs/checkin/checkin_state.dart';

/// Tela de check-in: atleta gera QR para o staff escanear.
class AthleteCheckinQrScreen extends StatefulWidget {
  final String sessionId;
  final String sessionTitle;

  const AthleteCheckinQrScreen({
    super.key,
    required this.sessionId,
    required this.sessionTitle,
  });

  @override
  State<AthleteCheckinQrScreen> createState() => _AthleteCheckinQrScreenState();
}

class _AthleteCheckinQrScreenState extends State<AthleteCheckinQrScreen> {
  Timer? _countdownTimer;
  int _remainingSeconds = 0;

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _startCountdown(int expiresAtMs) {
    _countdownTimer?.cancel();
    void tick() {
      if (!mounted) return;
      final now = DateTime.now().millisecondsSinceEpoch;
      final remaining = ((expiresAtMs - now) / 1000).ceil();
      setState(() => _remainingSeconds = remaining > 0 ? remaining : 0);
      if (remaining <= 0) _countdownTimer?.cancel();
    }

    tick();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) => tick());
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) =>
          sl<CheckinBloc>()..add(GenerateCheckinQr(sessionId: widget.sessionId)),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Check-in de Presença'),
        ),
        body: BlocConsumer<CheckinBloc, CheckinState>(
          listener: (context, state) {
            if (state is CheckinQrReady) {
              _startCountdown(state.token.expiresAtMs);
            }
          },
          builder: (context, state) => switch (state) {
            CheckinInitial() => _buildInitial(context),
            CheckinGenerating() => _buildLoading(),
            CheckinQrReady(:final token, :final encodedPayload) =>
              _buildQrReady(context, token, encodedPayload),
            CheckinConsuming() => _buildLoading(),
            CheckinSuccess() => _buildInitial(context),
            CheckinError(:final message) => _buildError(context, message),
          },
        ),
      ),
    );
  }

  Widget _buildInitial(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(DesignTokens.spacingLg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Text(
                      widget.sessionTitle,
                      style: theme.textTheme.titleMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: () => context.read<CheckinBloc>().add(
                            GenerateCheckinQr(sessionId: widget.sessionId),
                          ),
                      icon: const Icon(Icons.qr_code_2),
                      label: const Text('Gerar QR'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoading() =>
      const Center(child: CircularProgressIndicator());

  int _computeRemainingSeconds(int expiresAtMs) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return ((expiresAtMs - now) / 1000).ceil().clamp(0, 999999);
  }

  Widget _buildQrReady(
    BuildContext context,
    CheckinToken token,
    String encodedPayload,
  ) {
    final theme = Theme.of(context);
    // Use _remainingSeconds if countdown has run, else compute from token
    final displaySeconds = _remainingSeconds > 0 || _countdownTimer != null
        ? _remainingSeconds
        : _computeRemainingSeconds(token.expiresAtMs);
    final expired = displaySeconds <= 0;
    final minutes = displaySeconds ~/ 60;
    final seconds = displaySeconds % 60;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(DesignTokens.spacingLg),
      child: Column(
        children: [
          Text(
            widget.sessionTitle,
            style: theme.textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: expired
                  ? theme.colorScheme.errorContainer
                  : DesignTokens.success.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  expired ? Icons.timer_off : Icons.timer,
                  size: 18,
                  color: expired ? theme.colorScheme.error : DesignTokens.success,
                ),
                const SizedBox(width: 6),
                Text(
                  expired
                      ? 'QR Expirado — Gerar Novo'
                      : 'Expira em ${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: expired ? theme.colorScheme.error : DesignTokens.success,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          if (expired)
            Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.qr_code_2_rounded, size: 48, color: theme.colorScheme.outline),
                    const SizedBox(height: 8),
                    Text(
                      'QR Expirado',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                    Text(
                      'Gerar Novo',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            Container(
              padding: const EdgeInsets.all(DesignTokens.spacingMd),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
                boxShadow: [
                  BoxShadow(
                    color: theme.colorScheme.shadow.withValues(alpha: 0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: QrImageView(
                data: encodedPayload,
                version: QrVersions.auto,
                size: 200,
                backgroundColor: Colors.white,
              ),
            ),
          const SizedBox(height: 24),
          if (!expired)
            FilledButton.icon(
              onPressed: () => context.read<CheckinBloc>().add(
                    GenerateCheckinQr(sessionId: widget.sessionId),
                  ),
              icon: const Icon(Icons.refresh),
              label: const Text('Gerar Novo QR'),
            )
          else
            FilledButton.icon(
              onPressed: () => context.read<CheckinBloc>().add(
                    GenerateCheckinQr(sessionId: widget.sessionId),
                  ),
              icon: const Icon(Icons.qr_code_2),
              label: const Text('Gerar Novo QR'),
            ),
        ],
      ),
    );
  }

  Widget _buildError(BuildContext context, String message) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(DesignTokens.spacingLg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => context.read<CheckinBloc>().add(
                    GenerateCheckinQr(sessionId: widget.sessionId),
                  ),
              icon: const Icon(Icons.refresh),
              label: const Text('Tentar Novamente'),
            ),
          ],
        ),
      ),
    );
  }
}
