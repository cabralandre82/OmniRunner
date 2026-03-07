import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:omni_runner/core/auth/auth_repository.dart';
import 'package:omni_runner/core/router/app_router.dart';
import 'package:omni_runner/data/services/profile_data_service.dart';
import 'package:omni_runner/core/auth/user_identity_provider.dart';
import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/core/service_locator.dart';
import 'package:omni_runner/domain/entities/profile_entity.dart';
import 'package:omni_runner/domain/repositories/i_profile_repo.dart';
import 'package:omni_runner/l10n/l10n.dart';
import 'package:omni_runner/presentation/widgets/cached_avatar.dart';
import 'package:omni_runner/core/theme/design_tokens.dart';

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
  bool _busyAuth = false;
  bool _uploadingAvatar = false;
  bool _socialColumnsAvailable = false;
  String? _error;

  String _initialName = '';
  String _initialInsta = '';
  String _initialTiktok = '';

  int _badgeCount = 0;
  int _currentStreak = 0;
  double _totalKm = 0;
  int _level = 1;
  int _xp = 0;

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
      bool socialOk = false;
      if (p != null) {
        try {
          final row = await sl<ProfileDataService>().getSocialColumns(p.id);
          insta = row?['instagram_handle'] as String? ?? '';
          tiktok = row?['tiktok_handle'] as String? ?? '';
          socialOk = true;
        } on Exception {
          // Columns may not exist yet in production
        }
      }
      var displayName = p?.displayName ?? 'Runner';
      if (displayName.contains('@')) {
        displayName = displayName.split('@').first;
        if (displayName.isNotEmpty) {
          displayName = displayName[0].toUpperCase() + displayName.substring(1);
        }
      }
      _initialName = displayName;
      _initialInsta = insta;
      _initialTiktok = tiktok;
      if (p != null) {
        await _loadStats(p.id);
      }
      setState(() {
        _profile = p;
        _nameCtrl.text = displayName;
        _instaCtrl.text = insta;
        _tiktokCtrl.text = tiktok;
        _socialColumnsAvailable = socialOk;
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

  Future<void> _loadStats(String uid) async {
    try {
      final db = sl<SupabaseClient>();
      final badgesFuture = db.from('badges_earned').select('id').eq('user_id', uid);
      final progFuture = db.from('user_progressions').select('level, xp, current_streak_days').eq('user_id', uid).maybeSingle();
      final sessionsFuture = db.from('sessions').select('total_distance_m').eq('user_id', uid);

      final badges = await badgesFuture;
      final prog = await progFuture;
      final sessions = await sessionsFuture;

      double km = 0;
      for (final s in sessions) {
        km += (s['total_distance_m'] as num?)?.toDouble() ?? 0;
      }
      if (mounted) {
        setState(() {
          _badgeCount = badges.length;
          _level = (prog?['level'] as int?) ?? 1;
          _xp = (prog?['xp'] as int?) ?? 0;
          _currentStreak = (prog?['current_streak_days'] as int?) ?? 0;
          _totalKm = km / 1000;
        });
      }
    } on Exception catch (e) {
      AppLogger.debug('Profile stats load failed', tag: _tag, error: e);
    }
  }

  Future<void> _saveAll() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;

    final supaUser = sl<ProfileDataService>().currentUser;
    if (supaUser == null) {
      setState(() => _error = 'Você precisa estar autenticado para salvar.');
      return;
    }

    setState(() { _saving = true; _error = null; });
    try {
      final fields = <String, dynamic>{
        'display_name': name,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
      if (_socialColumnsAvailable) {
        fields['instagram_handle'] = _instaCtrl.text.trim();
        fields['tiktok_handle'] = _tiktokCtrl.text.trim();
      }
      final res = await sl<ProfileDataService>().updateProfile(supaUser.id, fields);

      if (res.isEmpty) {
        setState(() {
          _error = 'Não foi possível atualizar. Tente sair e entrar novamente.';
          _saving = false;
        });
        return;
      }

      if (!mounted) return;
      sl<UserIdentityProvider>().refresh();
      sl<UserIdentityProvider>().updateProfileName(name);
      final refreshed = await sl<IProfileRepo>().getMyProfile();
      if (!mounted) return;
      setState(() {
        _profile = refreshed;
        _nameCtrl.text = name;
        _saving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Perfil atualizado com sucesso'),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      AppLogger.error('Profile save failed: $e', tag: _tag, error: e);
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
      final bytes = await File(picked.path).readAsBytes();

      final publicUrl = await sl<ProfileDataService>().uploadAvatar(
        userId,
        ext,
        bytes,
      );

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
    if (_busyAuth) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.logout_rounded, color: DesignTokens.error, size: 40),
        title: const Text('Sair da conta?'),
        content: const Text(
          'Você será redirecionado para a tela de login. '
          'Seus dados não serão perdidos.',
        ),
        actions: [
          TextButton(
            onPressed: () => ctx.pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: DesignTokens.error),
            onPressed: () => ctx.pop(true),
            child: const Text('Sair'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busyAuth = true);
    try {
      final failure = await sl<AuthRepository>().signOut();
      if (!mounted) return;

      if (failure != null) {
        setState(() => _error = failure.message);
        return;
      }

      context.go(AppRoutes.root);
    } finally {
      if (mounted) setState(() => _busyAuth = false);
    }
  }

  Future<void> _requestDeleteAccount() async {
    if (_busyAuth) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.warning_rounded, color: DesignTokens.error, size: 40),
        title: const Text('Excluir conta permanentemente?'),
        content: const Text(
          'Todos os seus dados serão apagados permanentemente: '
          'corridas, desafios, OmniCoins e progresso.\n\n'
          'Esta ação não pode ser desfeita.',
        ),
        actions: [
          TextButton(
            onPressed: () => ctx.pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: DesignTokens.error),
            onPressed: () => ctx.pop(true),
            child: const Text('Excluir conta'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busyAuth = true);
    try {
      await sl<ProfileDataService>().requestDeleteAccount();
      if (!mounted) return;
      await sl<AuthRepository>().signOut();
      if (!mounted) return;
      context.go(AppRoutes.root);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Não foi possível excluir a conta. '
            'Entre em contato: suporte@omnirunner.app\n'
            'Erro: ${_friendlyError(e)}',
          ),
          duration: const Duration(seconds: 5),
        ),
      );
    } finally {
      if (mounted) setState(() => _busyAuth = false);
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

  bool get _hasUnsavedChanges =>
      _nameCtrl.text != _initialName ||
      _instaCtrl.text != _initialInsta ||
      _tiktokCtrl.text != _initialTiktok;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final identity = sl<UserIdentityProvider>();

    return PopScope(
      canPop: !_hasUnsavedChanges,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final shouldPop = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Descartar alterações?'),
            content: const Text('Suas alterações não salvas serão perdidas.'),
            actions: [
              TextButton(
                onPressed: () => ctx.pop(false),
                child: const Text('Cancelar'),
              ),
              TextButton(
                onPressed: () => ctx.pop(true),
                child: const Text('Descartar'),
              ),
            ],
          ),
        );
        if (shouldPop == true && context.mounted) context.pop();
      },
      child: Semantics(
      label: 'Tela de Perfil',
      child: Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.profile),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(DesignTokens.spacingMd),
              children: [
                // ── Avatar ──
                Center(
                  child: Stack(
                    children: [
                      CachedAvatar(
                        url: _profile?.avatarUrl,
                        fallbackText: _profile?.displayName ?? 'R',
                        radius: 52,
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
                              padding: const EdgeInsets.all(DesignTokens.spacingSm),
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

                // ── Edit display_name (athletes only) ──
                if (_profile?.userRole != 'ASSESSORIA_STAFF') ...[
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
                    onSubmitted: (_) => _saveAll(),
                  ),
                  const SizedBox(height: 12),
                ],

                if (_socialColumnsAvailable) ...[
                  const SizedBox(height: 28),
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
                ],
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
                    label: Text(context.l10n.save),
                  ),
                ),

                // ── Error ──
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Card(
                    color: DesignTokens.error.withValues(alpha: 0.1),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
                      side: BorderSide(color: DesignTokens.error.withValues(alpha: 0.3)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline,
                              color: DesignTokens.error, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _error!,
                              style: TextStyle(
                                  color: DesignTokens.error, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],

                // ── Achievements ──
                const SizedBox(height: 24),
                const Divider(),
                const SizedBox(height: DesignTokens.spacingSm),
                Text(
                  'Conquistas',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: cs.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: DesignTokens.spacingSm),
                Card(
                  elevation: 0,
                  color: cs.primaryContainer.withValues(alpha: 0.3),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: DesignTokens.spacingMd,
                      horizontal: DesignTokens.spacingSm,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _ProfileStat(
                          icon: Icons.trending_up_rounded,
                          value: 'Nível $_level',
                          label: '$_xp XP',
                          color: cs.primary,
                        ),
                        _ProfileStat(
                          icon: Icons.military_tech_rounded,
                          value: '$_badgeCount',
                          label: 'Badges',
                          color: DesignTokens.warning,
                        ),
                        _ProfileStat(
                          icon: Icons.local_fire_department_rounded,
                          value: '$_currentStreak',
                          label: 'Dias seguidos',
                          color: DesignTokens.error,
                        ),
                        _ProfileStat(
                          icon: Icons.directions_run_rounded,
                          value: '${_totalKm.toStringAsFixed(0)} km',
                          label: 'Total',
                          color: DesignTokens.success,
                        ),
                      ],
                    ),
                  ),
                ),

                // ── Sign out ──
                if (!identity.isAnonymous) ...[
                  const SizedBox(height: 32),
                  const Divider(),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _busyAuth ? null : _signOut,
                      icon: _busyAuth
                          ? const SizedBox(
                              width: 16, height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.logout_rounded),
                      label: Text(context.l10n.logout),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: DesignTokens.error,
                        side: const BorderSide(color: DesignTokens.error),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton.icon(
                      onPressed: _busyAuth ? null : _requestDeleteAccount,
                      icon: const Icon(Icons.delete_forever_rounded, size: 18),
                      label: Text(context.l10n.delete),
                      style: TextButton.styleFrom(
                        foregroundColor: DesignTokens.error,
                      ),
                    ),
                  ),
                ],
              ],
            ),
    ),
    ),
    );
  }
}

class _ProfileStat extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;

  const _ProfileStat({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}
