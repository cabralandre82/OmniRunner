import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:omni_runner/core/auth/user_identity_provider.dart';
import 'package:omni_runner/core/config/app_config.dart';
import 'package:omni_runner/core/errors/strava_failures.dart';
import 'package:omni_runner/core/service_locator.dart';
import 'package:omni_runner/domain/entities/coach_settings_entity.dart';

import 'package:omni_runner/domain/repositories/i_coach_settings_repo.dart';
import 'package:omni_runner/features/strava/domain/strava_auth_state.dart';
import 'package:omni_runner/features/strava/presentation/strava_connect_controller.dart';
import 'package:omni_runner/main.dart' show themeNotifier;
import 'package:omni_runner/presentation/screens/how_it_works_screen.dart';

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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Configurações'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                if (!widget.isStaff) ...[
                  _header('Integrações'),
                  const _StravaIntegrationTile(),
                  const Divider(height: 32),
                ],
                _header('Aparência'),
                ValueListenableBuilder<ThemeMode>(
                  valueListenable: themeNotifier,
                  builder: (_, mode, __) => Column(
                    children: [
                      RadioListTile<ThemeMode>(
                        title: const Text('Seguir sistema'),
                        secondary: const Icon(Icons.brightness_auto),
                        value: ThemeMode.system,
                        groupValue: mode,
                        onChanged: (v) => themeNotifier.setMode(v!),
                      ),
                      RadioListTile<ThemeMode>(
                        title: const Text('Claro'),
                        secondary: const Icon(Icons.light_mode),
                        value: ThemeMode.light,
                        groupValue: mode,
                        onChanged: (v) => themeNotifier.setMode(v!),
                      ),
                      RadioListTile<ThemeMode>(
                        title: const Text('Escuro'),
                        secondary: const Icon(Icons.dark_mode),
                        value: ThemeMode.dark,
                        groupValue: mode,
                        onChanged: (v) => themeNotifier.setMode(v!),
                      ),
                    ],
                  ),
                ),
                if (!widget.isStaff) ...[
                  const Divider(height: 32),
                  _header('Unidades'),
                  ListTile(
                    leading: const Icon(Icons.straighten),
                    title: const Text('Distância'),
                    subtitle: Text(_settings.useImperial
                        ? 'Milhas (mi)'
                        : 'Quilômetros (km)'),
                    trailing: Switch(
                      value: _settings.useImperial,
                      onChanged: (v) =>
                          _update(_settings.copyWith(useImperial: v)),
                    ),
                  ),
                  const Divider(height: 32),
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
                  const Divider(height: 32),
                  _header('Ajuda'),
                  ListTile(
                    leading: const Icon(Icons.help_outline_rounded),
                    title: const Text('Como Funciona'),
                    subtitle: const Text(
                      'Desafios, OmniCoins, verificação e integridade',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const HowItWorksScreen(),
                      ),
                    ),
                  ),
                ],
                if (kDebugMode) ...[
                  const Divider(height: 32),
                  _header('Auth Debug'),
                  const _AuthDebugCard(),
                ],
              ],
            ),
    );
  }

  Widget _header(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Text(
          text,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: Theme.of(context).colorScheme.primary,
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
      await controller.startConnect();
    } on IntegrationFailure catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao conectar: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disconnect() async {
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
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
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
          SnackBar(content: Text('Erro: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
              color: connected ? const Color(0xFFFC4C02) : Colors.grey.shade300,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.watch, color: Colors.white, size: 22),
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
                  width: 24,
                  height: 24,
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
                        backgroundColor: const Color(0xFFFC4C02),
                      ),
                    ),
        ),
        if (!connected && !needsReauth)
          Padding(
            padding: const EdgeInsets.fromLTRB(72, 0, 16, 12),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3E0),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFFCC80), width: 0.5),
              ),
              child: const Text(
                'Corra só com seu Garmin, Coros, Suunto ou Apple Watch! '
                'Conectando ao Strava, suas corridas são importadas '
                'automaticamente e contam para os desafios. '
                'GPS e ritmo cardíaco são verificados pelo anti-cheat.',
                style: TextStyle(fontSize: 12, color: Color(0xFF5D4037)),
              ),
            ),
          ),
        if (connected)
          Padding(
            padding: const EdgeInsets.fromLTRB(72, 0, 16, 12),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F5E9),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFA5D6A7), width: 0.5),
              ),
              child: const Text(
                'Suas corridas gravadas no relógio serão importadas '
                'automaticamente via Strava e contarão para seus desafios.',
                style: TextStyle(fontSize: 12, color: Color(0xFF2E7D32)),
              ),
            ),
          ),
      ],
    );
  }
}

/// Card displaying current auth state for debugging.
/// In debug builds with remote mode, shows "Copiar JWT" and "Ping verify-session".
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
    final identity = sl<UserIdentityProvider>();
    final user = identity.authUser;
    final mode = AppConfig.backendMode;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Card(
        color: mode == 'remote'
            ? Colors.green.shade50
            : Colors.grey.shade100,
        child: Padding(
          padding: const EdgeInsets.all(12),
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
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('Copiar JWT'),
                    onPressed: () => _copyJwt(context),
                  ),
                ),
                const SizedBox(height: 4),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: _pinging
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.network_ping, size: 16),
                    label: const Text('Ping verify-session'),
                    onPressed: _pinging ? null : _pingVerifySession,
                  ),
                ),
                if (_pingResult != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: SelectableText(
                      _pingResult!,
                      style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                    ),
                  ),
                ],
                const SizedBox(height: 4),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: _pingingAnalytics
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.analytics_outlined, size: 16),
                    label: const Text('Ping submit-analytics'),
                    onPressed: _pingingAnalytics ? null : _pingSubmitAnalytics,
                  ),
                ),
                if (_pingAnalyticsResult != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: SelectableText(
                      _pingAnalyticsResult!,
                      style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                    ),
                  ),
                ],
                const SizedBox(height: 4),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: _pingingLeaderboard
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.leaderboard_outlined, size: 16),
                    label: const Text('Ping compute-leaderboard'),
                    onPressed: _pingingLeaderboard ? null : _pingComputeLeaderboard,
                  ),
                ),
                if (_pingLeaderboardResult != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(6),
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
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    if (token == null || token.isEmpty) {
      setState(() => _pingResult = 'Erro: nenhuma sessao ativa — JWT indisponivel');
      return;
    }

    final url = AppConfig.supabaseUrl;
    final anonKey = AppConfig.supabaseAnonKey;
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
      } catch (_) {
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
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    if (token == null || token.isEmpty) {
      setState(() => _pingLeaderboardResult = 'Erro: nenhuma sessao ativa — JWT indisponivel');
      return;
    }

    final url = AppConfig.supabaseUrl;
    final anonKey = AppConfig.supabaseAnonKey;
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
      } catch (_) {
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
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    if (token == null || token.isEmpty) {
      setState(() => _pingAnalyticsResult = 'Erro: nenhuma sessao ativa — JWT indisponivel');
      return;
    }

    final url = AppConfig.supabaseUrl;
    final anonKey = AppConfig.supabaseAnonKey;
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
      } catch (_) {
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

  void _copyJwt(BuildContext context) {
    try {
      final token = Supabase.instance.client.auth.currentSession?.accessToken;
      if (token == null || token.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nenhuma sessao ativa — JWT indisponivel')),
        );
        return;
      }
      Clipboard.setData(ClipboardData(text: token));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('JWT copiado para o clipboard'),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao copiar JWT: $e')),
      );
    }
  }

  Widget _row(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
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
