import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:omni_runner/core/service_locator.dart';
import 'package:omni_runner/core/theme/design_tokens.dart';
import 'package:omni_runner/core/utils/error_messages.dart';
import 'package:omni_runner/domain/entities/announcement_entity.dart';
import 'package:omni_runner/domain/repositories/i_announcement_repo.dart';
import 'package:omni_runner/domain/usecases/announcements/create_announcement.dart';

/// Form to create or edit an announcement (staff only).
class AnnouncementCreateScreen extends StatefulWidget {
  final String groupId;
  final AnnouncementEntity? existing;

  const AnnouncementCreateScreen({
    super.key,
    required this.groupId,
    this.existing,
  });

  @override
  State<AnnouncementCreateScreen> createState() =>
      _AnnouncementCreateScreenState();
}

class _AnnouncementCreateScreenState extends State<AnnouncementCreateScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();

  bool _pinned = false;
  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _titleController.text = e.title;
      _bodyController.text = e.body;
      _pinned = e.pinned;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      if (_isEdit) {
        final existing = widget.existing;
        if (existing == null) return;
        final repo = sl<IAnnouncementRepo>();
        final updated = existing.copyWith(
          title: _titleController.text.trim(),
          body: _bodyController.text.trim(),
          pinned: _pinned,
        );
        await repo.update(updated);
      } else {
        final createAnnouncement = sl<CreateAnnouncement>();
        await createAnnouncement(
          groupId: widget.groupId,
          title: _titleController.text.trim(),
          body: _bodyController.text.trim(),
          pinned: _pinned,
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Aviso publicado com sucesso!')),
        );
        context.pop(true);
      }
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = ErrorMessages.humanize(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Editar Aviso' : 'Novo Aviso'),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.only(right: DesignTokens.spacingMd),
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            IconButton(
              onPressed: _save,
              icon: const Icon(Icons.check),
              tooltip: 'Salvar',
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(DesignTokens.spacingMd),
          children: [
            TextFormField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'Título',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.sentences,
              maxLines: 1,
              validator: (v) {
                if (v == null || v.trim().length < 2) {
                  return 'O título deve ter pelo menos 2 caracteres';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _bodyController,
              decoration: const InputDecoration(
                labelText: 'Conteúdo',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
              textCapitalization: TextCapitalization.sentences,
              maxLines: 6,
              validator: (v) {
                if (v == null || v.trim().isEmpty) {
                  return 'O conteúdo é obrigatório';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              value: _pinned,
              onChanged: _saving
                  ? null
                  : (v) => setState(() => _pinned = v),
              title: const Text('Fixar no topo'),
              subtitle: const Text(
                'Avisos fixados aparecem primeiro no mural',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(
                _error ?? '',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.error,
                ),
              ),
            ],
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
              label: Text(_saving ? 'Salvando…' : 'Salvar'),
            ),
          ],
        ),
      ),
    );
  }
}
