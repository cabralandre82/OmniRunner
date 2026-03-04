import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:omni_runner/core/service_locator.dart';
import 'package:omni_runner/core/theme/design_tokens.dart';
import 'package:omni_runner/domain/entities/member_status_entity.dart';
import 'package:omni_runner/domain/repositories/i_crm_repo.dart';
import 'package:omni_runner/presentation/widgets/shimmer_loading.dart';

/// Tela do atleta exibindo seu próprio status (read-only).
class AthleteMyStatusScreen extends StatefulWidget {
  final String groupId;
  final String userId;

  const AthleteMyStatusScreen({
    super.key,
    required this.groupId,
    required this.userId,
  });

  @override
  State<AthleteMyStatusScreen> createState() => _AthleteMyStatusScreenState();
}

class _AthleteMyStatusScreenState extends State<AthleteMyStatusScreen> {
  MemberStatusEntity? _status;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final status = await sl<ICrmRepo>().getStatus(
        groupId: widget.groupId,
        userId: widget.userId,
      );
      if (mounted) {
        setState(() {
          _status = status;
          _loading = false;
        });
      }
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Meu Status'),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const ShimmerListLoader();
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(DesignTokens.spacingLg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: Theme.of(context).colorScheme.error),
              const SizedBox(height: 16),
              Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _loadStatus,
                icon: const Icon(Icons.refresh),
                label: const Text('Tentar novamente'),
              ),
            ],
          ),
        ),
      );
    }
    if (_status == null) {
      return Center(
        child: Text(
          'Status não definido',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadStatus,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [_buildStatusCard()],
      ),
    );
  }

  Widget _buildStatusCard() {
    final status = _status!;
    final (label, color) = _statusBadge(status.status);

    return Padding(
      padding: const EdgeInsets.all(DesignTokens.spacingMd),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(DesignTokens.spacingLg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
                    ),
                    child: Text(
                      label,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'Última atualização: ${DateFormat('d MMM yyyy, HH:mm', 'pt_BR').format(status.updatedAt)}',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  (String label, Color color) _statusBadge(MemberStatusValue status) {
    return switch (status) {
      MemberStatusValue.active => ('Ativo', DesignTokens.success),
      MemberStatusValue.paused => ('Pausado', DesignTokens.warning),
      MemberStatusValue.injured => ('Lesionado', DesignTokens.error),
      MemberStatusValue.inactive => ('Inativo', DesignTokens.textMuted),
      MemberStatusValue.trial => ('Teste', DesignTokens.primary),
    };
  }
}
