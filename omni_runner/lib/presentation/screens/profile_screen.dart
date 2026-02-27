import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:omni_runner/core/auth/auth_repository.dart';
import 'package:omni_runner/core/auth/user_identity_provider.dart';
import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/core/service_locator.dart';
import 'package:omni_runner/domain/entities/profile_entity.dart';
import 'package:omni_runner/domain/repositories/i_profile_repo.dart';
import 'package:omni_runner/presentation/screens/auth_gate.dart';

/// Screen showing the user's Supabase profile with editable display_name.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  static const _tag = 'Profile';
  final _nameCtrl = TextEditingController();
  final _instaCtrl = TextEditingController();
  final _tiktokCtrl = TextEditingController();
  ProfileEntity? _profile;
  bool _loading = true;
  bool _saving = false;
  bool _uploadingAvatar = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _instaCtrl.dispose();
    _tiktokCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final p = await sl<IProfileRepo>().getMyProfile();
      if (!mounted) return;
      String insta = '';
      String tiktok = '';
      if (p != null) {
        try {
          final row = await Supabase.instance.client
              .from('profiles')
              .select('instagram_handle, tiktok_handle')
              .eq('id', p.id)
              .maybeSingle();
          insta = row?['instagram_handle'] as String? ?? '';
          tiktok = row?['tiktok_handle'] as String? ?? '';
        } on Exception {
          // Best effort
        }
      }
      setState(() {
        _profile = p;
        _nameCtrl.text = p?.displayName ?? 'Runner';
        _instaCtrl.text = insta;
        _tiktokCtrl.text = tiktok;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _friendlyError(e);
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;

    setState(() { _saving = true; _error = null; });
    try {
      final updated = await sl<IProfileRepo>().upsertMyProfile(
        ProfilePatch(displayName: name),
      );
      if (!mounted) return;
      sl<UserIdentityProvider>().refresh();
      setState(() { _profile = updated; _saving = false; });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nome atualizado com sucesso'),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _friendlyError(e);
        _saving = false;
      });
    }
  }

  Future<void> _saveAll() async {
    await _save();
    await _saveSocial();
  }

  Future<void> _saveSocial() async {
    setState(() { _saving = true; _error = null; });
    try {
      final uid = sl<UserIdentityProvider>().userId;
      await Supabase.instance.client.from('profiles').update({
        'instagram_handle': _instaCtrl.text.trim(),
        'tiktok_handle': _tiktokCtrl.text.trim(),
      }).eq('id', uid);
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Redes sociais atualizadas'),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _friendlyError(e);
        _saving = false;
      });
    }
  }

  Future<void> _pickAndUploadAvatar() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 80,
    );
    if (picked == null || !mounted) return;

    setState(() => _uploadingAvatar = true);

    try {
      final userId = sl<UserIdentityProvider>().userId;
      final ext = picked.path.split('.').last;
      final path = 'avatars/$userId.$ext';
      final bytes = await File(picked.path).readAsBytes();

      await Supabase.instance.client.storage
          .from('avatars')
          .uploadBinary(path, bytes,
              fileOptions: const FileOptions(upsert: true));

      final publicUrl =
          Supabase.instance.client.storage.from('avatars').getPublicUrl(path);

      final updated = await sl<IProfileRepo>().upsertMyProfile(
        ProfilePatch(avatarUrl: publicUrl),
      );

      if (!mounted) return;
      sl<UserIdentityProvider>().refresh();
      setState(() {
        _profile = updated;
        _uploadingAvatar = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Foto atualizada')),
      );
    } catch (e) {
      AppLogger.error('Avatar upload failed: $e', tag: _tag, error: e);
      if (!mounted) return;
      setState(() {
        _uploadingAvatar = false;
        _error = 'Falha ao enviar foto. Tente novamente.';
      });
    }
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.logout_rounded, color: Colors.red.shade600, size: 40),
        title: const Text('Sair da conta?'),
        content: const Text(
          'Você será redirecionado para a tela de login. '
          'Seus dados não serão perdidos.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sair'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final failure = await sl<AuthRepository>().signOut();
    if (!mounted) return;

    if (failure != null) {
      setState(() => _error = failure.message);
      return;
    }

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const AuthGate()),
      (_) => false,
    );
  }

  Future<void> _requestDeleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.warning_rounded, color: Colors.red.shade700, size: 40),
        title: const Text('Excluir conta permanentemente?'),
        content: const Text(
          'Todos os seus dados serão apagados permanentemente: '
          'corridas, desafios, OmniCoins e progresso.\n\n'
          'Esta ação não pode ser desfeita.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Excluir conta'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await Supabase.instance.client.functions.invoke(
        'delete-account',
        body: {},
      );
      if (!mounted) return;
      await sl<AuthRepository>().signOut();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => const AuthGate()),
        (_) => false,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Não foi possível excluir a conta. '
            'Entre em contato: suporte@omnirunner.com.br\n'
            'Erro: ${_friendlyError(e)}',
          ),
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  String _friendlyError(Object e) {
    final s = e.toString().toLowerCase();
    if (s.contains('socketexception') || s.contains('network')) {
      return 'Sem conexao de rede. Tente novamente.';
    }
    if (s.contains('permission') || s.contains('rls') || s.contains('403')) {
      return 'Permissao negada. Verifique sua autenticacao.';
    }
    if (s.contains('401') || s.contains('jwt')) {
      return 'Sessao expirada. Reinicie o app.';
    }
    if (s.contains('no authenticated user')) {
      return 'Voce nao esta autenticado. Funcionalidade indisponivel no modo offline.';
    }
    return 'Erro inesperado. Tente novamente.';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final identity = sl<UserIdentityProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Meu Perfil'),
        backgroundColor: cs.inversePrimary,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // ── Avatar ──
                Center(
                  child: Stack(
                    children: [
                      if (_profile?.avatarUrl != null &&
                          _profile!.avatarUrl!.isNotEmpty)
                        CircleAvatar(
                          radius: 52,
                          backgroundImage:
                              NetworkImage(_profile!.avatarUrl!),
                        )
                      else
                        CircleAvatar(
                          radius: 52,
                          backgroundColor: cs.primaryContainer,
                          child: Text(
                            _initials(_profile?.displayName ?? 'R'),
                            style: TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                              color: cs.primary,
                            ),
                          ),
                        ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Material(
                          color: cs.primary,
                          shape: const CircleBorder(),
                          child: InkWell(
                            onTap: _uploadingAvatar
                                ? null
                                : _pickAndUploadAvatar,
                            customBorder: const CircleBorder(),
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: _uploadingAvatar
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.camera_alt,
                                      size: 16, color: Colors.white),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    _profile?.displayName ?? 'Runner',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 4),
                Center(
                  child: Text(
                    identity.authUser.email ?? '',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ),
                const SizedBox(height: 24),

                // ── Edit display_name ──
                Text('Alterar nome',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: cs.primary)),
                const SizedBox(height: 8),
                TextField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nome de exibição',
                    border: OutlineInputBorder(),
                  ),
                  maxLength: 50,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _save(),
                ),
                const SizedBox(height: 12),
                const SizedBox(height: 28),

                // ── Social handles ──
                Text('Redes sociais',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: cs.primary)),
                const SizedBox(height: 4),
                Text(
                  'Compartilhe com seus amigos de corrida',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _instaCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Instagram',
                    prefixIcon: Icon(Icons.camera_alt_outlined),
                    hintText: 'seu_usuario',
                    border: OutlineInputBorder(),
                  ),
                  maxLength: 30,
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _tiktokCtrl,
                  decoration: const InputDecoration(
                    labelText: 'TikTok',
                    prefixIcon: Icon(Icons.music_note_rounded),
                    hintText: 'seu_usuario',
                    border: OutlineInputBorder(),
                  ),
                  maxLength: 30,
                  textInputAction: TextInputAction.done,
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _saving ? null : _saveAll,
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.save),
                    label: const Text('Salvar perfil'),
                  ),
                ),

                // ── Error ──
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Card(
                    color: Colors.red.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline,
                              color: Colors.red.shade700, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _error!,
                              style: TextStyle(
                                  color: Colors.red.shade800, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],

                // ── Sign out ──
                if (!identity.isAnonymous) ...[
                  const SizedBox(height: 32),
                  const Divider(),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _signOut,
                      icon: const Icon(Icons.logout_rounded),
                      label: const Text('Sair da conta'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton.icon(
                      onPressed: _requestDeleteAccount,
                      icon: const Icon(Icons.delete_forever_rounded, size: 18),
                      label: const Text('Excluir minha conta'),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.red.shade300,
                      ),
                    ),
                  ),
                ],
              ],
            ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : 'R';
  }
}
