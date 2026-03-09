import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:omni_runner/core/auth/user_identity_provider.dart';
import 'package:omni_runner/core/config/app_config.dart';
import 'package:omni_runner/core/errors/strava_failures.dart';
import 'package:omni_runner/core/utils/error_messages.dart';
import 'package:omni_runner/core/service_locator.dart';
import 'package:omni_runner/core/theme/design_tokens.dart';
import 'package:omni_runner/domain/entities/coach_settings_entity.dart';
import 'package:omni_runner/l10n/l10n.dart';

import 'package:omni_runner/domain/repositories/i_coach_settings_repo.dart';
import 'package:omni_runner/features/strava/domain/strava_auth_state.dart';
import 'package:omni_runner/features/strava/presentation/strava_connect_controller.dart';
import 'package:omni_runner/main.dart' show themeNotifier;
import 'package:omni_runner/core/logging/logger.dart';
import 'package:go_router/go_router.dart';
import 'package:omni_runner/core/router/app_router.dart';

class SettingsScreen extends StatefulWidget {
  final bool isStaff;
  const SettingsScreen({super.key, this.isStaff = false});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  CoachSettingsEntity _settings = const CoachSettingsEntity();
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final s = await sl<ICoachSettingsRepo>().load();
    if (mounted) setState(() { _settings = s; _loading = false; });
  }

  Future<void> _update(CoachSettingsEntity s) async {
    setState(() => _settings = s);
    await sl<ICoachSettingsRepo>().save(s);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Tela de Configurações',
      child: Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.settings),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: DesignTokens.spacingSm),
              children: [
                if (!widget.isStaff) ...[
                  _header('Integrações'),
                  const _StravaIntegrationTile(),
                  const Divider(height: DesignTokens.spacingXl),
                ],
                _header('Aparência'),
                ValueListenableBuilder<ThemeMode>(
                  valueListenable: themeNotifier,
                  builder: (_, mode, __) => RadioGroup<ThemeMode>(
                    groupValue: mode,
                    onChanged: (v) { if (v != null) themeNotifier.setMode(v); },
                    child: Column(
                      children: [
                        RadioListTile<ThemeMode>(
                          title: Text(context.l10n.systemMode),
                          secondary: const Icon(Icons.brightness_auto),
                          value: ThemeMode.system,
                        ),
                        RadioListTile<ThemeMode>(
                          title: Text(context.l10n.lightMode),
                          secondary: const Icon(Icons.light_mode),
                          value: ThemeMode.light,
                        ),
                        RadioListTile<ThemeMode>(
                          title: Text(context.l10n.darkMode),
                          secondary: const Icon(Icons.dark_mode),
                          value: ThemeMode.dark,
                        ),
                      ],
                    ),
                  ),
                ),
                if (!widget.isStaff) ...[
                  const Divider(height: DesignTokens.spacingXl),
                  _header('Unidades'),
                  ListTile(
                    leading: const Icon(Icons.straighten),
                    title: Text(context.l10n.distance),
                    subtitle: Text(_settings.useImperial
                        ? 'Milhas (mi)'
                        : 'Quilômetros (km)'),
                    trailing: Switch(
                      value: _settings.useImperial,
                      onChanged: (v) =>
                          _update(_settings.copyWith(useImperial: v)),
                    ),
                  ),
                  const Divider(height: DesignTokens.spacingXl),
                  _header('Privacidade'),
                  SwitchListTile(
                    title: const Text('Perfil visível no ranking'),
                    subtitle: const Text(
                      'Permite que outros vejam seu nome nos leaderboards',
                    ),
                    secondary: const Icon(Icons.visibility),
                    value: _settings.profileVisibleInRanking,
                    onChanged: (v) =>
                        _update(_settings.copyWith(profileVisibleInRanking: v)),
                  ),
                  SwitchListTile(
                    title: const Text('Compartilhar atividade na assessoria'),
                    subtitle: const Text(
                      'Suas corridas aparecem no feed da assessoria',
                    ),
                    secondary: const Icon(Icons.share),
                    value: _settings.shareActivityInFeed,
                    onChanged: (v) =>
                        _update(_settings.copyWith(shareActivityInFeed: v)),
                  ),
                  const Divider(height: DesignTokens.spacingXl),
                  _header('Ajuda'),
                  ListTile(
                    leading: const Icon(Icons.help_outline_rounded),
                    title: Text(context.l10n.howItWorks),
                    subtitle: const Text(
                      'Desafios, OmniCoins, verificação e integridade',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push(AppRoutes.howItWorks),
                  ),
                  ListTile(
                    leading: const Icon(Icons.privacy_tip_outlined),
                    title: const Text('Política de Privacidade'),
                    subtitle: const Text(
                      'Como seus dados são coletados e utilizados',
                    ),
                    trailing: const Icon(Icons.open_in_new, size: 18),
                    onTap: () => launchUrl(
                      Uri.parse('https://omnirunner.app/privacidade'),
                      mode: LaunchMode.externalApplication,
                    ),
                  ),
                ],
                if (kDebugMode) ...[
                  const Divider(height: DesignTokens.spacingXl),
                  _header('Auth Debug'),
                  const _AuthDebugCard(),
                  const SizedBox(height: DesignTokens.spacingMd),
                  ListTile(
                    leading: const Icon(Icons.bug_report),
                    title: Text(context.l10n.diagnostics),
                    subtitle: const Text('Status do app, conexões e ambiente'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push(AppRoutes.diagnostics),
                  ),
                ],
              ],
            ),
    ),
    );
  }

  Widget _header(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(
          DesignTokens.spacingMd,
          DesignTokens.spacingSm,
          DesignTokens.spacingMd,
          DesignTokens.spacingXs,
        ),
        child: Text(
          text,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
              ),
        ),
      );
}

class _StravaIntegrationTile extends StatefulWidget {
  const _StravaIntegrationTile();

  @override
  State<_StravaIntegrationTile> createState() => _StravaIntegrationTileState();
}

class _StravaIntegrationTileState extends State<_StravaIntegrationTile> {
  StravaAuthState _state = const StravaDisconnected();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  Future<void> _loadState() async {
    final controller = sl<StravaConnectController>();
    final s = await controller.getState();
    if (mounted) setState(() => _state = s);
  }

  Future<void> _connect() async {
    setState(() => _busy = true);
    try {
      final controller = sl<StravaConnectController>();
      final result = await controller.startConnect();
      if (mounted) {
        setState(() => _state = result.state);
        final msg = result.importedCount > 0
            ? '${result.importedCount} corridas importadas do Strava!'
            : 'Strava conectado como ${result.state.athleteName}!';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: DesignTokens.warning),
        );
      }
    } on AuthCancelled {
      await _loadState();
      if (mounted && _state is StravaConnected) {
        final controller = sl<StravaConnectController>();
        controller.retryBackfillIfNeeded().ignore();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Strava conectado como ${(_state as StravaConnected).athleteName}!',
            ),
            backgroundColor: DesignTokens.warning,
          ),
        );
      }
    } on IntegrationFailure {
      await _loadState();
      if (mounted && _state is StravaConnected) {
        final controller = sl<StravaConnectController>();
        controller.retryBackfillIfNeeded().ignore();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Strava conectado como ${(_state as StravaConnected).athleteName}!',
            ),
            backgroundColor: DesignTokens.warning,
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erro ao conectar Strava. Tente novamente.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disconnect() async {
    final cs = Theme.of(context).colorScheme;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Desconectar Strava'),
        content: const Text(
          'Suas corridas do relógio (Garmin, Coros, etc.) não serão mais '
          'importadas automaticamente e não contarão para desafios. '
          'Corridas feitas no app continuam funcionando normalmente.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: cs.error),
            child: const Text('Desconectar'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _busy = true);
    try {
      final controller = sl<StravaConnectController>();
      await controller.disconnect();
      await _loadState();
    } on IntegrationFailure catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ErrorMessages.humanize(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final connected = _state is StravaConnected;
    final athleteName =
        _state is StravaConnected ? (_state as StravaConnected).athleteName : null;
    final needsReauth = _state is StravaReauthRequired;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: connected
                  ? DesignTokens.warning
                  : cs.onSurface.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
            ),
            child: Icon(Icons.watch, color: cs.onPrimary, size: 22),
          ),
          title: const Text('Strava'),
          subtitle: Text(
            connected
                ? 'Conectado como $athleteName'
                : needsReauth
                    ? 'Reconexão necessária'
                    : 'Conecte para correr só com o relógio',
          ),
          trailing: _busy
              ? const SizedBox(
                  width: DesignTokens.spacingLg,
                  height: DesignTokens.spacingLg,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : connected
                  ? TextButton(
                      onPressed: _disconnect,
                      child: const Text('Desconectar'),
                    )
                  : FilledButton.icon(
                      onPressed: _connect,
                      icon: const Icon(Icons.link, size: 18),
                      label: const Text('Conectar'),
                      style: FilledButton.styleFrom(
                        backgroundColor: DesignTokens.warning,
                      ),
                    ),
        ),
        if (!connected && !needsReauth)
          Padding(
            padding: const EdgeInsets.fromLTRB(72, 0, DesignTokens.spacingMd, DesignTokens.spacingMd),
            child: Container(
              padding: const EdgeInsets.all(DesignTokens.spacingSm),
              decoration: BoxDecoration(
                color: DesignTokens.warning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
                border: Border.all(color: DesignTokens.warning.withValues(alpha: 0.3), width: 0.5),
              ),
              child: const Text(
                'Corra só com seu Garmin, Coros, Suunto ou Apple Watch! '
                'Conectando ao Strava, suas corridas são importadas '
                'automaticamente e contam para os desafios. '
                'GPS e ritmo cardíaco são verificados pelo anti-cheat.',
                style: TextStyle(fontSize: 12, color: DesignTokens.warning),
              ),
            ),
          ),
        if (connected)
          Padding(
            padding: const EdgeInsets.fromLTRB(72, 0, DesignTokens.spacingMd, DesignTokens.spacingMd),
            child: Container(
              padding: const EdgeInsets.all(DesignTokens.spacingSm),
              decoration: BoxDecoration(
                color: DesignTokens.success.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
                border: Border.all(color: DesignTokens.success.withValues(alpha: 0.3), width: 0.5),
              ),
              child: const Text(
                'Suas corridas gravadas no relógio serão importadas '
                'automaticamente via Strava e contarão para seus desafios.',
                style: TextStyle(fontSize: 12, color: DesignTokens.success),
              ),
            ),
          ),
      ],
    );
  }
}

/// Card displaying current auth state for debugging.
/// In debug builds with remote mode, shows ping buttons for edge functions.
class _AuthDebugCard extends StatefulWidget {
  const _AuthDebugCard();

  @override
  State<_AuthDebugCard> createState() => _AuthDebugCardState();
}

class _AuthDebugCardState extends State<_AuthDebugCard> {
  bool _pinging = false;
  String? _pingResult;
  bool _pingingAnalytics = false;
  String? _pingAnalyticsResult;
  bool _pingingLeaderboard = false;
  String? _pingLeaderboardResult;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final identity = sl<UserIdentityProvider>();
    final user = identity.authUser;
    final mode = AppConfig.backendMode;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignTokens.spacingMd,
        vertical: DesignTokens.spacingXs,
      ),
      child: Card(
        color: mode == 'remote'
            ? DesignTokens.success.withValues(alpha: 0.1)
            : cs.surfaceContainerHighest,
        child: Padding(
          padding: const EdgeInsets.all(DesignTokens.spacingMd),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _row(context, 'backendMode', mode),
              _row(context, 'isSignedIn', '${user.id.isNotEmpty}'),
              _row(context, 'userId', _truncate(user.id, 20)),
              _row(context, 'email', user.email ?? '—'),
              _row(context, 'isAnonymous', '${user.isAnonymous}'),
              _row(context, 'displayName', user.displayName),
              if (kDebugMode && mode == 'remote') ...[
                const SizedBox(height: DesignTokens.spacingSm),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: _pinging
                        ? const SizedBox(
                            width: DesignTokens.spacingMd,
                            height: DesignTokens.spacingMd,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.network_ping, size: 16),
                    label: const Text('Ping verify-session'),
                    onPressed: _pinging ? null : _pingVerifySession,
                  ),
                ),
                if (_pingResult != null) ...[
                  const SizedBox(height: DesignTokens.spacingSm),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(DesignTokens.spacingSm),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
                    ),
                    child: SelectableText(
                      _pingResult!,
                      style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                    ),
                  ),
                ],
                const SizedBox(height: DesignTokens.spacingXs),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: _pingingAnalytics
                        ? const SizedBox(
                            width: DesignTokens.spacingMd,
                            height: DesignTokens.spacingMd,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.analytics_outlined, size: 16),
                    label: const Text('Ping submit-analytics'),
                    onPressed: _pingingAnalytics ? null : _pingSubmitAnalytics,
                  ),
                ),
                if (_pingAnalyticsResult != null) ...[
                  const SizedBox(height: DesignTokens.spacingSm),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(DesignTokens.spacingSm),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
                    ),
                    child: SelectableText(
                      _pingAnalyticsResult!,
                      style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                    ),
                  ),
                ],
                const SizedBox(height: DesignTokens.spacingXs),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: _pingingLeaderboard
                        ? const SizedBox(
                            width: DesignTokens.spacingMd,
                            height: DesignTokens.spacingMd,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.leaderboard_outlined, size: 16),
                    label: const Text('Ping compute-leaderboard'),
                    onPressed: _pingingLeaderboard ? null : _pingComputeLeaderboard,
                  ),
                ),
                if (_pingLeaderboardResult != null) ...[
                  const SizedBox(height: DesignTokens.spacingSm),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(DesignTokens.spacingSm),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
                    ),
                    child: SelectableText(
                      _pingLeaderboardResult!,
                      style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pingVerifySession() async {
    final token = sl<SupabaseClient>().auth.currentSession?.accessToken;
    if (token == null || token.isEmpty) {
      setState(() => _pingResult = 'Erro: nenhuma sessao ativa — JWT indisponivel');
      return;
    }

    const url = AppConfig.supabaseUrl;
    const anonKey = AppConfig.supabaseAnonKey;
    if (url.isEmpty || anonKey.isEmpty) {
      setState(() => _pingResult = 'Erro: SUPABASE_URL ou ANON_KEY nao configurados');
      return;
    }

    setState(() {
      _pinging = true;
      _pingResult = null;
    });

    try {
      final response = await http
          .post(
            Uri.parse('$url/functions/v1/verify-session'),
            headers: {
              'apikey': anonKey,
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: '{}',
          )
          .timeout(const Duration(seconds: 10));

      String body;
      try {
        final decoded = jsonDecode(response.body);
        body = const JsonEncoder.withIndent('  ').convert(decoded);
      } catch (e) {
      AppLogger.warn('Caught error', tag: 'SettingsScreen', error: e);
        body = response.body;
      }

      if (!mounted) return;
      setState(() => _pingResult = 'HTTP ${response.statusCode}\n$body');
    } on Exception catch (e) {
      if (!mounted) return;
      final msg = e.toString().replaceAll(RegExp(r'Bearer\s+\S+'), 'Bearer ***');
      setState(() => _pingResult = 'Erro: $msg');
    } finally {
      if (mounted) setState(() => _pinging = false);
    }
  }

  Future<void> _pingComputeLeaderboard() async {
    final token = sl<SupabaseClient>().auth.currentSession?.accessToken;
    if (token == null || token.isEmpty) {
      setState(() => _pingLeaderboardResult = 'Erro: nenhuma sessao ativa — JWT indisponivel');
      return;
    }

    const url = AppConfig.supabaseUrl;
    const anonKey = AppConfig.supabaseAnonKey;
    if (url.isEmpty || anonKey.isEmpty) {
      setState(() => _pingLeaderboardResult = 'Erro: SUPABASE_URL ou ANON_KEY nao configurados');
      return;
    }

    setState(() {
      _pingingLeaderboard = true;
      _pingLeaderboardResult = null;
    });

    try {
      final response = await http
          .post(
            Uri.parse('$url/functions/v1/compute-leaderboard'),
            headers: {
              'apikey': anonKey,
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: '{}',
          )
          .timeout(const Duration(seconds: 10));

      String body;
      try {
        final decoded = jsonDecode(response.body);
        body = const JsonEncoder.withIndent('  ').convert(decoded);
      } catch (e) {
      AppLogger.warn('Caught error', tag: 'SettingsScreen', error: e);
        body = response.body;
      }

      if (!mounted) return;
      setState(() => _pingLeaderboardResult = 'HTTP ${response.statusCode}\n$body');
    } on Exception catch (e) {
      if (!mounted) return;
      final msg = e.toString().replaceAll(RegExp(r'Bearer\s+\S+'), 'Bearer ***');
      setState(() => _pingLeaderboardResult = 'Erro: $msg');
    } finally {
      if (mounted) setState(() => _pingingLeaderboard = false);
    }
  }

  Future<void> _pingSubmitAnalytics() async {
    final token = sl<SupabaseClient>().auth.currentSession?.accessToken;
    if (token == null || token.isEmpty) {
      setState(() => _pingAnalyticsResult = 'Erro: nenhuma sessao ativa — JWT indisponivel');
      return;
    }

    const url = AppConfig.supabaseUrl;
    const anonKey = AppConfig.supabaseAnonKey;
    if (url.isEmpty || anonKey.isEmpty) {
      setState(() => _pingAnalyticsResult = 'Erro: SUPABASE_URL ou ANON_KEY nao configurados');
      return;
    }

    setState(() {
      _pingingAnalytics = true;
      _pingAnalyticsResult = null;
    });

    try {
      final payload = jsonEncode({
        'event': 'audit_ping',
        'ts': DateTime.now().toUtc().toIso8601String(),
        'meta': {'source': 'app_ping', 'step': 46},
      });

      final response = await http
          .post(
            Uri.parse('$url/functions/v1/submit-analytics'),
            headers: {
              'apikey': anonKey,
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: payload,
          )
          .timeout(const Duration(seconds: 10));

      String body;
      try {
        final decoded = jsonDecode(response.body);
        body = const JsonEncoder.withIndent('  ').convert(decoded);
      } catch (e) {
      AppLogger.warn('Caught error', tag: 'SettingsScreen', error: e);
        body = response.body;
      }

      if (!mounted) return;
      setState(() => _pingAnalyticsResult = 'HTTP ${response.statusCode}\n$body');
    } on Exception catch (e) {
      if (!mounted) return;
      final msg = e.toString().replaceAll(RegExp(r'Bearer\s+\S+'), 'Bearer ***');
      setState(() => _pingAnalyticsResult = 'Erro: $msg');
    } finally {
      if (mounted) setState(() => _pingingAnalytics = false);
    }
  }

  Widget _row(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: DesignTokens.spacingXs),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  String _truncate(String s, int max) =>
      s.length <= max ? s : '${s.substring(0, max)}...';
}
