import 'package:flutter/material.dart';

import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/core/service_locator.dart';
import 'package:omni_runner/core/theme/design_tokens.dart';
import 'package:omni_runner/domain/entities/device_link_entity.dart';
import 'package:omni_runner/domain/usecases/wearable/link_device.dart';
import 'package:omni_runner/presentation/widgets/shimmer_loading.dart';

class AthleteDeviceLinkScreen extends StatefulWidget {
  final String athleteUserId;
  final String groupId;

  const AthleteDeviceLinkScreen({
    super.key,
    required this.athleteUserId,
    required this.groupId,
  });

  @override
  State<AthleteDeviceLinkScreen> createState() =>
      _AthleteDeviceLinkScreenState();
}

class _AthleteDeviceLinkScreenState extends State<AthleteDeviceLinkScreen> {
  final _linkDevice = sl<LinkDevice>();

  List<DeviceLinkEntity>? _links;
  bool _loading = true;
  String? _error;

  static const _providers = ['garmin', 'apple', 'polar', 'suunto', 'trainingpeaks'];
  static const _providerLabels = {
    'garmin': 'Garmin',
    'apple': 'Apple Watch',
    'polar': 'Polar',
    'suunto': 'Suunto',
    'trainingpeaks': 'TrainingPeaks',
  };
  static const _providerIcons = {
    'garmin': Icons.watch,
    'apple': Icons.watch_outlined,
    'polar': Icons.monitor_heart_outlined,
    'suunto': Icons.explore_outlined,
    'trainingpeaks': Icons.fitness_center,
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final links = await _linkDevice.list(widget.athleteUserId);
      if (!mounted) return;
      setState(() {
        _links = links;
        _loading = false;
      });
    } catch (e, st) {
      AppLogger.error('DeviceLink load failed', error: e, stack: st);
      if (!mounted) return;
      setState(() {
        _error = 'Erro ao carregar dispositivos';
        _loading = false;
      });
    }
  }

  String? _linkedId(String provider) {
    final match = _links?.where(
        (l) => deviceProviderToString(l.provider) == provider);
    return match != null && match!.isNotEmpty ? match!.first.id : null;
  }

  Future<void> _toggleLink(String provider) async {
    final existingId = _linkedId(provider);
    try {
      if (existingId != null) {
        await _linkDevice.unlink(existingId);
      } else {
        await _linkDevice.call(groupId: widget.groupId, provider: provider);
      }
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(existingId != null
              ? '${_providerLabels[provider]} desconectado'
              : '${_providerLabels[provider]} conectado'),
        ),
      );
    } catch (e, st) {
      AppLogger.error('DeviceLink toggle failed', error: e, stack: st);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Erro ao alterar dispositivo')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Dispositivos')),
      body: _loading
          ? const ShimmerListLoader()
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline,
                          size: 48, color: theme.colorScheme.error),
                      const SizedBox(height: 16),
                      Text(_error!,
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: theme.colorScheme.error)),
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: _load,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Tentar Novamente'),
                      ),
                    ],
                  ),
                )
              : _links != null && _links!.isEmpty && _providers.isEmpty
                  ? _buildEmpty(theme)
                  : _buildList(theme),
    );
  }

  Widget _buildEmpty(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(DesignTokens.spacingXl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.watch_outlined, size: 64, color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4)),
            const SizedBox(height: 16),
            Text('Nenhum dispositivo conectado', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Conecte seu relógio ou sensor para sincronizar treinos',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => _load(),
              icon: const Icon(Icons.add),
              label: const Text('Conectar Dispositivo'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList(ThemeData theme) {
    return ListView.separated(
      padding: const EdgeInsets.all(DesignTokens.spacingMd),
      itemCount: _providers.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final provider = _providers[index];
        final linked = _linkedId(provider) != null;
        final linkEntity = _links?.where(
            (l) => deviceProviderToString(l.provider) == provider);
        final linkedDate = linkEntity != null && linkEntity!.isNotEmpty
            ? linkEntity!.first.linkedAt
            : null;

        return Card(
          child: ListTile(
            leading: Icon(
              _providerIcons[provider] ?? Icons.watch,
              color: linked
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outline,
            ),
            title: Text(_providerLabels[provider] ?? provider),
            subtitle: linked && linkedDate != null
                ? Text(
                    'Conectado em ${linkedDate.day.toString().padLeft(2, '0')}/${linkedDate.month.toString().padLeft(2, '0')}/${linkedDate.year}')
                : const Text('Não conectado'),
            trailing: FilledButton.tonal(
              onPressed: () => _toggleLink(provider),
              child: Text(linked ? 'Desconectar' : 'Conectar'),
            ),
          ),
        );
      },
    );
  }
}
