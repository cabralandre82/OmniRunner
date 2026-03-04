import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import 'package:omni_runner/core/service_locator.dart';
import 'package:omni_runner/core/theme/design_tokens.dart';
import 'package:omni_runner/domain/entities/announcement_entity.dart';
import 'package:omni_runner/presentation/blocs/announcement_detail/announcement_detail_bloc.dart';
import 'package:omni_runner/presentation/blocs/announcement_detail/announcement_detail_event.dart';
import 'package:omni_runner/presentation/blocs/announcement_detail/announcement_detail_state.dart';
import 'package:omni_runner/presentation/screens/announcement_create_screen.dart';

/// Detail view of an announcement with auto-read and staff controls.
class AnnouncementDetailScreen extends StatelessWidget {
  final String announcementId;
  final bool isStaff;

  const AnnouncementDetailScreen({
    super.key,
    required this.announcementId,
    required this.isStaff,
  });

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) =>
          sl<AnnouncementDetailBloc>()
            ..add(LoadAnnouncementDetail(announcementId)),
      child: BlocConsumer<AnnouncementDetailBloc, AnnouncementDetailState>(
        listenWhen: (_, next) =>
            next is AnnouncementDeleted || next is AnnouncementDetailError,
        listener: (context, state) {
          switch (state) {
            case AnnouncementDeleted():
              if (context.mounted) {
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Aviso excluído')),
                );
              }
            case _:
              break;
          }
        },
        builder: (context, state) => _AnnouncementDetailView(
          announcementId: announcementId,
          isStaff: isStaff,
        ),
      ),
    );
  }
}

class _AnnouncementDetailView extends StatelessWidget {
  final String announcementId;
  final bool isStaff;

  const _AnnouncementDetailView({
    required this.announcementId,
    required this.isStaff,
  });

  Future<void> _openEdit(
    BuildContext context,
    AnnouncementEntity announcement,
  ) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AnnouncementCreateScreen(
          groupId: announcement.groupId,
          existing: announcement,
        ),
      ),
    );
    if (result == true && context.mounted) {
      context
          .read<AnnouncementDetailBloc>()
          .add(LoadAnnouncementDetail(announcementId));
    }
  }

  void _showDeleteDialog(
    BuildContext context,
    AnnouncementDetailBloc bloc,
    AnnouncementEntity announcement,
  ) {
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir aviso'),
        content: const Text(
          'Tem certeza que deseja excluir este aviso? '
          'Esta ação não pode ser desfeita.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('Excluir'),
          ),
        ],
      ),
    ).then((ok) {
      if (ok == true) {
        bloc.add(const DeleteAnnouncement());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm', 'pt_BR');

    return Scaffold(
      appBar: AppBar(
        title: BlocBuilder<AnnouncementDetailBloc, AnnouncementDetailState>(
          builder: (context, state) {
            return Text(
              switch (state) {
                AnnouncementDetailLoaded(:final announcement) =>
                  announcement.title,
                _ => 'Aviso',
              },
            );
          },
        ),
        actions: [
          if (isStaff)
            BlocBuilder<AnnouncementDetailBloc, AnnouncementDetailState>(
              builder: (context, state) {
                return switch (state) {
                  AnnouncementDetailLoaded(:final announcement) => PopupMenuButton<
                      String>(
                    onSelected: (value) {
                      final bloc =
                          context.read<AnnouncementDetailBloc>();
                      switch (value) {
                        case 'edit':
                          _openEdit(context, announcement);
                          break;
                        case 'pin':
                          bloc.add(const TogglePin());
                          break;
                        case 'delete':
                          _showDeleteDialog(
                            context,
                            bloc,
                            announcement,
                          );
                          break;
                      }
                    },
                    itemBuilder: (ctx) => [
                      const PopupMenuItem(
                        value: 'edit',
                        child: Row(
                          children: [
                            Icon(Icons.edit),
                            SizedBox(width: 12),
                            Text('Editar'),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'pin',
                        child: Row(
                          children: [
                            Icon(
                              announcement.pinned
                                  ? Icons.push_pin
                                  : Icons.push_pin_outlined,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              announcement.pinned ? 'Desafixar' : 'Fixar',
                            ),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete_outline, color: cs.error),
                            const SizedBox(width: 12),
                            Text(
                              'Excluir',
                              style: TextStyle(color: cs.error),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  _ => const SizedBox.shrink(),
                };
              },
            ),
        ],
      ),
      body: BlocBuilder<AnnouncementDetailBloc, AnnouncementDetailState>(
        builder: (context, state) {
          return switch (state) {
            AnnouncementDetailInitial() || AnnouncementDetailLoading() => const Center(
                child: CircularProgressIndicator(),
              ),
            AnnouncementDetailError(:final message) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(DesignTokens.spacingLg),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline_rounded, size: 48, color: cs.error),
                      const SizedBox(height: 16),
                      Text(
                        message,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: cs.error,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            AnnouncementDetailLoaded(
              :final announcement,
              :final readStats,
            ) =>
              SingleChildScrollView(
                padding: const EdgeInsets.all(DesignTokens.spacingMd),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(DesignTokens.spacingMd),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              announcement.title,
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              announcement.body,
                              style: theme.textTheme.bodyLarge,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              '${announcement.authorDisplayName ?? 'Desconhecido'} • ${dateFormat.format(announcement.createdAt)}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: cs.outline,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (isStaff && readStats != null) ...[
                      const SizedBox(height: 16),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(DesignTokens.spacingMd),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Lido por ${readStats.readCount} de ${readStats.totalMembers} (${readStats.readRate.toStringAsFixed(0)}%)',
                                style: theme.textTheme.bodyMedium,
                              ),
                              const SizedBox(height: 8),
                              LinearProgressIndicator(
                                value: readStats.readRate / 100,
                                backgroundColor: cs.surfaceContainerHighest,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    _ConfirmReadButton(
                      isRead: announcement.isRead,
                      onConfirm: () => context
                          .read<AnnouncementDetailBloc>()
                          .add(const ConfirmRead()),
                    ),
                  ],
                ),
              ),
            AnnouncementDeleted() => const SizedBox.shrink(),
          };
        },
      ),
    );
  }
}

class _ConfirmReadButton extends StatelessWidget {
  final bool isRead;
  final VoidCallback onConfirm;

  const _ConfirmReadButton({
    required this.isRead,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (isRead) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle, color: cs.primary),
          const SizedBox(width: 8),
          Text(
            'Leitura confirmada',
            style: TextStyle(
              color: cs.primary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      );
    }

    return FilledButton.icon(
      onPressed: onConfirm,
      icon: const Icon(Icons.check),
      label: const Text('Confirmar leitura'),
    );
  }
}
