import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:omni_runner/core/config/app_config.dart';
import 'package:omni_runner/core/service_locator.dart';
import 'package:omni_runner/domain/repositories/i_sync_repo.dart';
import 'package:omni_runner/core/theme/design_tokens.dart';

class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  final _items = <_DiagItem>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _collect();
  }

  Future<void> _collect() async {
    final items = <_DiagItem>[];

    try {
      final pkg = await PackageInfo.fromPlatform();
      items.add(_DiagItem('Versão do app', '${pkg.version}+${pkg.buildNumber}'));
    } catch (e) {
      items.add(_DiagItem('Versão do app', 'erro: $e'));
    }

    items.add(_DiagItem('Ambiente', AppConfig.isProd ? 'prod' : 'dev'));
    items.add(_DiagItem('Backend mode', AppConfig.backendMode));

    items.add(_DiagItem(
      'Supabase',
      AppConfig.isSupabaseReady ? 'conectado' : 'desconectado',
      ok: AppConfig.isSupabaseReady,
    ));

    if (AppConfig.isSupabaseReady) {
      try {
        final user = Supabase.instance.client.auth.currentUser;
        items.add(_DiagItem(
          'Auth',
          user != null ? 'autenticado (${user.email ?? user.id.substring(0, 8)})' : 'não autenticado',
          ok: user != null,
        ));
      } catch (e) {
        items.add(_DiagItem('Auth', 'erro: $e', ok: false));
      }
    }

    try {
      sl<ISyncRepo>();
      items.add(const _DiagItem('Sync service', 'disponível', ok: true));
    } catch (e) {
      items.add(const _DiagItem('Sync service', 'indisponível', ok: false));
    }

    items.add(_DiagItem(
      'Sentry',
      AppConfig.isSentryConfigured ? 'ativo' : 'desativado',
      ok: AppConfig.isSentryConfigured,
    ));

    items.add(const _DiagItem('Debug mode', kDebugMode ? 'sim' : 'não'));

    if (mounted) {
      setState(() {
        _items
          ..clear()
          ..addAll(items);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (!kDebugMode) {
      return Scaffold(
        appBar: AppBar(title: const Text('Diagnóstico')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Text(
              'Diagnóstico não disponível',
              style: TextStyle(fontSize: 16),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Diagnóstico')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () async {
                setState(() => _loading = true);
                await _collect();
              },
              child: ListView.separated(
                padding: const EdgeInsets.all(DesignTokens.spacingMd),
                itemCount: _items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final item = _items[i];
                  return Card(
                    child: ListTile(
                      leading: item.ok == null
                          ? Icon(Icons.info_outline, color: cs.onSurfaceVariant)
                          : item.ok!
                              ? Icon(Icons.check_circle, color: cs.primary)
                              : Icon(Icons.error_outline, color: cs.error),
                      title: Text(item.label,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                              )),
                      subtitle: Text(item.value,
                          style: Theme.of(context).textTheme.bodyLarge),
                    ),
                  );
                },
              ),
            ),
    );
  }
}

class _DiagItem {
  final String label;
  final String value;
  final bool? ok;

  const _DiagItem(this.label, this.value, {this.ok});
}
