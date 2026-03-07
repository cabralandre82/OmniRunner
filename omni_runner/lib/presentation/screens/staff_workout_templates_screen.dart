import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:omni_runner/core/router/app_router.dart';
import 'package:omni_runner/core/service_locator.dart';
import 'package:omni_runner/domain/entities/workout_template_entity.dart';
import 'package:omni_runner/domain/repositories/i_workout_repo.dart';
import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/presentation/widgets/shimmer_loading.dart';
import 'package:omni_runner/core/theme/design_tokens.dart';

/// Lists workout templates for the current coaching group.
/// Staff can tap to edit or use FAB to create new templates.
class StaffWorkoutTemplatesScreen extends StatefulWidget {
  final String groupId;

  const StaffWorkoutTemplatesScreen({
    super.key,
    required this.groupId,
  });

  @override
  State<StaffWorkoutTemplatesScreen> createState() =>
      _StaffWorkoutTemplatesScreenState();
}

class _StaffWorkoutTemplatesScreenState
    extends State<StaffWorkoutTemplatesScreen> {
  List<WorkoutTemplateEntity>? _templates;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadTemplates();
  }

  Future<void> _loadTemplates() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final templates = await sl<IWorkoutRepo>().listTemplates(widget.groupId);
      if (mounted) {
        setState(() {
          _templates = templates;
          _loading = false;
        });
      }
    } catch (e, stack) {
      AppLogger.error(
        'Erro ao listar templates',
        tag: 'WorkoutTemplatesScreen',
        error: e,
        stack: stack,
      );
      if (mounted) {
        setState(() {
          _error = 'Erro ao carregar templates: $e';
          _loading = false;
        });
      }
    }
  }

  void _openBuilder({String? templateId}) async {
    final uri = Uri(
      path: AppRoutes.staffWorkoutBuilderPath(widget.groupId),
      queryParameters: templateId != null ? {'templateId': templateId} : null,
    );
    final result = await context.push<bool>(uri.toString());
    if (result == true && mounted) {
      _loadTemplates();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Templates de Treino'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _openBuilder(),
            tooltip: 'Novo template',
          ),
        ],
      ),
      body: _buildBody(theme),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openBuilder(),
        icon: const Icon(Icons.add),
        label: const Text('Novo Template'),
      ),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_loading) {
      return ListView(children: List.generate(5, (_) => const ShimmerCard()));
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(DesignTokens.spacingLg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline_rounded,
                size: 48,
                color: theme.colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _loadTemplates,
                icon: const Icon(Icons.refresh),
                label: const Text('Tentar novamente'),
              ),
            ],
          ),
        ),
      );
    }

    final templates = _templates ?? [];
    if (templates.isEmpty) {
      return _buildEmpty(theme);
    }

    return RefreshIndicator(
      onRefresh: _loadTemplates,
      child: ListView.builder(
        padding: const EdgeInsets.all(DesignTokens.spacingMd),
        itemCount: templates.length,
        itemBuilder: (context, index) {
          final template = templates[index];
          return _TemplateCard(
            template: template,
            onTap: () => _openBuilder(templateId: template.id),
          );
        },
      ),
    );
  }

  Widget _buildEmpty(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(DesignTokens.spacingXl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.fitness_center_outlined, size: 64, color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4)),
            const SizedBox(height: 16),
            Text('Nenhum template criado', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Crie seu primeiro template de treino',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => _openBuilder(),
              icon: const Icon(Icons.add),
              label: const Text('Criar Template'),
            ),
          ],
        ),
      ),
    );
  }
}

class _TemplateCard extends StatelessWidget {
  final WorkoutTemplateEntity template;
  final VoidCallback onTap;

  const _TemplateCard({required this.template, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final blockCount = template.blocks.length;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
        child: Padding(
          padding: const EdgeInsets.all(DesignTokens.spacingMd),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                template.name,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (template.description != null &&
                  template.description!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  template.description!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.view_list_outlined,
                      size: 16, color: cs.primary),
                  const SizedBox(width: 4),
                  Text(
                    '$blockCount bloco${blockCount != 1 ? 's' : ''}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: cs.primary,
                      fontWeight: FontWeight.w500,
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
}
