import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:omni_runner/domain/entities/token_intent_entity.dart';
import 'package:omni_runner/presentation/blocs/staff_qr/staff_qr_bloc.dart';
import 'package:omni_runner/presentation/blocs/staff_qr/staff_qr_event.dart';
import 'package:omni_runner/presentation/blocs/staff_qr/staff_qr_state.dart';
import 'package:omni_runner/core/theme/design_tokens.dart';

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
  EmissionCapacity? _capacity;
  BadgeCapacity? _badgeCapacity;
  bool _capacityLoading = true;

  bool get _isIssue => widget.type == TokenIntentType.issueToAthlete;
  bool get _isBadge => widget.type == TokenIntentType.champBadgeActivate;
  bool get _hasInventoryControl => _isIssue || _isBadge;

  @override
  void initState() {
    super.initState();
    if (_isIssue) {
      context
          .read<StaffQrBloc>()
          .add(LoadEmissionCapacity(widget.groupId));
    } else if (_isBadge) {
      context
          .read<StaffQrBloc>()
          .add(LoadBadgeCapacity(widget.groupId));
    } else {
      _capacityLoading = false;
    }
  }

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
          if (state is StaffQrCapacityLoaded) {
            setState(() {
              _capacity = state.capacity;
              _capacityLoading = false;
            });
          }
          if (state is StaffQrBadgeCapacityLoaded) {
            setState(() {
              _badgeCapacity = state.capacity;
              _capacityLoading = false;
            });
          }
          if (state is StaffQrGenerated) {
            _startCountdown(state.payload);
            final cap = _capacity;
            if (_isIssue && cap != null) {
              setState(() {
                _capacity = EmissionCapacity(
                  availableTokens:
                      cap.availableTokens - state.payload.amount,
                  lifetimeIssued:
                      cap.lifetimeIssued + state.payload.amount,
                  lifetimeBurned: cap.lifetimeBurned,
                );
              });
            }
            final badgeCap = _badgeCapacity;
            if (_isBadge && badgeCap != null) {
              setState(() {
                _badgeCapacity = BadgeCapacity(
                  availableBadges:
                      badgeCap.availableBadges - state.payload.amount,
                  lifetimePurchased: badgeCap.lifetimePurchased,
                  lifetimeActivated:
                      badgeCap.lifetimeActivated + state.payload.amount,
                );
              });
            }
          }
          if (state is StaffQrError) {
            if (!state.message.contains('capacidade') &&
                !state.message.contains('badges')) {
              _capacityLoading = false;
            }
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
          StaffQrCapacityLoaded() => _buildForm(context, theme),
          StaffQrBadgeCapacityLoaded() => _buildForm(context, theme),
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
    final cap = _capacity;
    final badgeCap = _badgeCapacity;
    final exceedsCoinCapacity = _isIssue &&
        cap != null &&
        _amount > cap.availableTokens;
    final exceedsBadgeCapacity = _isBadge &&
        badgeCap != null &&
        badgeCap.availableBadges <= 0;
    final exceedsCapacity = exceedsCoinCapacity || exceedsBadgeCapacity;

    return Padding(
      padding: const EdgeInsets.all(DesignTokens.spacingLg),
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
          if (_hasInventoryControl) ...[
            const SizedBox(height: 20),
            if (_isIssue) _buildCapacityCard(theme),
            if (_isBadge) _buildBadgeCapacityCard(theme),
          ],
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
                    style: theme.textTheme.headlineMedium?.copyWith(
                      color: exceedsCapacity
                          ? theme.colorScheme.error
                          : null,
                    ),
                  ),
                ),
                IconButton.outlined(
                  onPressed: () => setState(() => _amount++),
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            if (exceedsCoinCapacity) ...[
              const SizedBox(height: 8),
              Text(
                'Quantidade excede o saldo disponível '
                '(${cap.availableTokens})',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 32),
          ],
          FilledButton.icon(
            onPressed: exceedsCapacity
                ? null
                : () => context.read<StaffQrBloc>().add(
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

  Widget _buildCapacityCard(ThemeData theme) {
    if (_capacityLoading) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(DesignTokens.spacingMd),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 12),
              Text(
                'Carregando saldo...',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final cap = _capacity ?? EmissionCapacity.empty;
    final available = cap.availableTokens;
    final low = available > 0 && available <= 10;

    return Card(
      color: available == 0
          ? theme.colorScheme.errorContainer
          : low
              ? DesignTokens.warning.withValues(alpha: 0.08)
              : DesignTokens.success.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: DesignTokens.spacingMd, vertical: 12),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  available == 0
                      ? Icons.warning_amber_rounded
                      : Icons.account_balance_wallet,
                  size: 20,
                  color: available == 0
                      ? theme.colorScheme.error
                      : low
                          ? DesignTokens.warning
                          : DesignTokens.success,
                ),
                const SizedBox(width: 8),
                Text(
                  'Disponível: $available OmniCoins',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: available == 0
                        ? theme.colorScheme.error
                        : low
                            ? DesignTokens.warning
                            : DesignTokens.success,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _statChip(theme, 'Distribuídos', cap.lifetimeIssued),
                _statChip(theme, 'Devolvidos', cap.lifetimeBurned),
              ],
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: InkWell(
                onTap: () {
                  setState(() => _capacityLoading = true);
                  context
                      .read<StaffQrBloc>()
                      .add(LoadEmissionCapacity(widget.groupId));
                },
                child: Padding(
                  padding: const EdgeInsets.all(DesignTokens.spacingXs),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.refresh, size: 14,
                          color: theme.colorScheme.primary),
                      const SizedBox(width: 4),
                      Text(
                        'Atualizar',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statChip(ThemeData theme, String label, int value) {
    return Column(
      children: [
        Text(
          '$value',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildBadgeCapacityCard(ThemeData theme) {
    if (_capacityLoading) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(DesignTokens.spacingMd),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 12),
              Text(
                'Carregando badges...',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final cap = _badgeCapacity ?? BadgeCapacity.empty;
    final available = cap.availableBadges;
    final low = available > 0 && available <= 3;

    return Card(
      color: available == 0
          ? theme.colorScheme.errorContainer
          : low
              ? DesignTokens.warning.withValues(alpha: 0.08)
              : DesignTokens.info.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: DesignTokens.spacingMd, vertical: 12),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  available == 0
                      ? Icons.warning_amber_rounded
                      : Icons.military_tech,
                  size: 20,
                  color: available == 0
                      ? theme.colorScheme.error
                      : low
                          ? DesignTokens.warning
                          : DesignTokens.info,
                ),
                const SizedBox(width: 8),
                Text(
                  'Disponível: $available badge${available != 1 ? 's' : ''}',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: available == 0
                        ? theme.colorScheme.error
                        : low
                            ? DesignTokens.warning
                            : DesignTokens.info,
                  ),
                ),
              ],
            ),
            if (available == 0) ...[
              const SizedBox(height: 8),
              Text(
                'Adquira mais badges pelo portal da assessoria.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _statChip(theme, 'Comprados', cap.lifetimePurchased),
                _statChip(theme, 'Ativados', cap.lifetimeActivated),
              ],
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: InkWell(
                onTap: () {
                  setState(() => _capacityLoading = true);
                  context
                      .read<StaffQrBloc>()
                      .add(LoadBadgeCapacity(widget.groupId));
                },
                child: Padding(
                  padding: const EdgeInsets.all(DesignTokens.spacingXs),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.refresh, size: 14,
                          color: theme.colorScheme.primary),
                      const SizedBox(width: 4),
                      Text(
                        'Atualizar',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
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
      padding: const EdgeInsets.all(DesignTokens.spacingLg),
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
                  : DesignTokens.success.withValues(alpha: 0.08),
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
                      ? 'Expirado'
                      : 'Expira em ${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: expired ? theme.colorScheme.error : DesignTokens.success,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          if (!expired)
            Container(
              padding: const EdgeInsets.all(DesignTokens.spacingMd),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
                border: Border.all(color: DesignTokens.textMuted),
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
                color: DesignTokens.surface,
                borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
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
            onPressed: () {
              context.read<StaffQrBloc>().add(const ResetStaffQr());
              if (_hasInventoryControl) {
                Future.microtask(() {
                  if (mounted) {
                    setState(() => _capacityLoading = true);
                    if (_isIssue) {
                      context
                          .read<StaffQrBloc>()
                          .add(LoadEmissionCapacity(widget.groupId));
                    } else if (_isBadge) {
                      context
                          .read<StaffQrBloc>()
                          .add(LoadBadgeCapacity(widget.groupId));
                    }
                  }
                });
              }
            },
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
