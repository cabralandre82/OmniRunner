import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:omni_runner/core/auth/user_identity_provider.dart';
import 'package:omni_runner/core/config/app_config.dart';
import 'package:omni_runner/core/service_locator.dart';
import 'package:omni_runner/domain/entities/coach_settings_entity.dart';
import 'package:omni_runner/domain/repositories/i_coach_settings_repo.dart';

/// Screen for toggling audio coach announcement categories.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
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
        title: const Text('Audio Coach'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                _header('Voice announcements'),
                SwitchListTile(
                  title: const Text('Kilometer announcements'),
                  subtitle: const Text('Announce every km with pace'),
                  secondary: const Icon(Icons.straighten),
                  value: _settings.kmEnabled,
                  onChanged: (v) => _update(_settings.copyWith(kmEnabled: v)),
                ),
                SwitchListTile(
                  title: const Text('Ghost alerts'),
                  subtitle: const Text('Alert when you pass or are passed by the ghost'),
                  secondary: const Icon(Icons.people_alt),
                  value: _settings.ghostEnabled,
                  onChanged: (v) => _update(_settings.copyWith(ghostEnabled: v)),
                ),
                SwitchListTile(
                  title: const Text('Periodic updates'),
                  subtitle: const Text('Time-based updates every 5 min'),
                  secondary: const Icon(Icons.timer),
                  value: _settings.periodicEnabled,
                  onChanged: (v) => _update(_settings.copyWith(periodicEnabled: v)),
                ),
                const Divider(height: 32),
                _header('Auth Debug'),
                const _AuthDebugCard(),
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
