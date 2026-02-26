import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:omni_runner/core/analytics/product_event_tracker.dart';
import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/core/service_locator.dart';

/// Onboarding screen for ASSESSORIA_STAFF users.
///
/// Two paths:
///   1. **Criar assessoria** — form (name + city) → `fn_create_assessoria` RPC
///   2. **Entrar como professor** — search/QR/code → `fn_join_as_professor` RPC
///
/// Both paths set `onboarding_state` to READY and call [onComplete].
class StaffSetupScreen extends StatefulWidget {
  final VoidCallback onComplete;
  final VoidCallback? onBack;

  const StaffSetupScreen({super.key, required this.onComplete, this.onBack});

  @override
  State<StaffSetupScreen> createState() => _StaffSetupScreenState();
}

enum _StaffMode { choose, create, join }

// ---------------------------------------------------------------------------
// Lightweight model for search results (same shape as fn_search_coaching_groups)
// ---------------------------------------------------------------------------

class _GroupInfo {
  final String id;
  final String name;
  final String city;
  final String coachDisplayName;
  final int memberCount;

  const _GroupInfo({
    required this.id,
    required this.name,
    required this.city,
    required this.coachDisplayName,
    required this.memberCount,
  });

  factory _GroupInfo.fromJson(Map<String, dynamic> j) => _GroupInfo(
        id: j['id'] as String,
        name: j['name'] as String? ?? '',
        city: (j['city'] as String?) ?? '',
        coachDisplayName: (j['coach_display_name'] as String?) ?? 'Coach',
        memberCount: (j['member_count'] as num?)?.toInt() ?? 0,
      );
}

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

class _StaffSetupScreenState extends State<StaffSetupScreen> {
  static const _tag = 'StaffSetup';
  static final _uuidRe = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    caseSensitive: false,
  );

  _StaffMode _mode = _StaffMode.choose;
  bool _busy = false;
  String? _error;

  // ── Create mode ──
  final _nameCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();

  // ── Join mode ──
  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  List<_GroupInfo> _results = [];
  bool _searching = false;

  SupabaseClient get _client => Supabase.instance.client;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _cityCtrl.dispose();
    _searchCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  // ── Create assessoria ────────────────────────────────────────────────────

  Future<void> _createAssessoria() async {
    final name = _nameCtrl.text.trim();
    if (name.length < 3) {
      setState(() => _error = 'O nome precisa ter pelo menos 3 caracteres.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      for (var attempt = 1; attempt <= 3; attempt++) {
        try {
          await _client.rpc('fn_create_assessoria', params: {
            'p_name': name,
            'p_city': _cityCtrl.text.trim(),
          });
          break;
        } catch (e) {
          AppLogger.warn('fn_create_assessoria attempt $attempt/3: $e', tag: _tag);
          if (attempt == 3) rethrow;
          await Future<void>.delayed(Duration(milliseconds: 500 * attempt));
        }
      }
      AppLogger.info('Created assessoria "$name"', tag: _tag);
      await _setReady();
      sl<ProductEventTracker>().track(ProductEvents.onboardingCompleted, {
        'role': 'ASSESSORIA_STAFF',
        'method': 'create_assessoria',
      });
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          icon: Icon(Icons.check_circle_outline,
              size: 48, color: Colors.green.shade600),
          title: const Text('Assessoria criada!'),
          content: const Text(
            'Sua assessoria foi criada com sucesso e está '
            'aguardando aprovação da plataforma Omni Runner.\n\n'
            'Você será notificado quando a aprovação for concluída. '
            'Enquanto isso, atletas ainda não poderão encontrar '
            'sua assessoria na busca.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Entendi'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      widget.onComplete();
    } catch (e) {
      AppLogger.error('Create assessoria failed: $e', tag: _tag, error: e);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Não foi possível criar a assessoria. Verifique sua conexão e tente novamente.';
      });
    }
  }

  // ── Join as professor ────────────────────────────────────────────────────

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    final trimmed = query.trim();
    if (trimmed.length < 2) {
      setState(() {
        _results = [];
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    _debounce = Timer(const Duration(milliseconds: 400), () {
      _search(trimmed);
    });
  }

  Future<void> _search(String query) async {
    try {
      final res = await _client.rpc(
        'fn_search_coaching_groups',
        params: {'p_query': query},
      );
      final list = (res as List<dynamic>)
          .map((r) => _GroupInfo.fromJson(r as Map<String, dynamic>))
          .toList();
      if (mounted) {
        setState(() {
          _results = list;
          _searching = false;
        });
      }
    } catch (e) {
      AppLogger.error('Search failed: $e', tag: _tag, error: e);
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _joinGroup(String groupId, String groupName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Solicitar entrada como professor?'),
        content: Text(
          'Sua solicitação será enviada para a assessoria '
          '"$groupName". O administrador precisará aprovar sua entrada.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Solicitar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final res = await _client.rpc(
        'fn_request_join',
        params: {'p_group_id': groupId, 'p_role': 'professor'},
      );
      final status = (res as Map<String, dynamic>?)?['status'] as String?;

      if (status == 'already_member') {
        AppLogger.info('Already a member of $groupId', tag: _tag);
        await _setReady();
        if (!mounted) return;
        widget.onComplete();
        return;
      }

      if (status == 'already_requested') {
        if (!mounted) return;
        setState(() => _busy = false);
        _showRequestSent(groupName, alreadyExists: true);
        return;
      }

      AppLogger.info('Requested to join $groupId as professor', tag: _tag);
      sl<ProductEventTracker>().track(ProductEvents.onboardingCompleted, {
        'role': 'ASSESSORIA_STAFF',
        'method': 'request_join_professor',
      });
      await _setReady();
      if (!mounted) return;
      _showRequestSent(groupName, alreadyExists: false);
    } catch (e) {
      AppLogger.error('Join request as professor failed: $e', tag: _tag, error: e);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Não foi possível enviar a solicitação. Tente novamente.';
      });
    }
  }

  void _showRequestSent(String groupName, {required bool alreadyExists}) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: Icon(
          alreadyExists ? Icons.info_outline : Icons.check_circle_outline,
          size: 48,
          color: alreadyExists ? Colors.orange : Colors.green,
        ),
        title: Text(
          alreadyExists
              ? 'Solicitação já enviada'
              : 'Solicitação enviada!',
        ),
        content: Text(
          alreadyExists
              ? 'Você já tem uma solicitação pendente para "$groupName". '
                'Aguarde a aprovação do administrador.'
              : 'Sua solicitação para entrar como professor em '
                '"$groupName" foi enviada. O administrador da assessoria '
                'irá analisar e aprovar sua entrada.',
        ),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              widget.onComplete();
            },
            child: const Text('Entendi'),
          ),
        ],
      ),
    );
  }

  Future<void> _scanQr() async {
    final scanned = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const _QrScannerPage()),
    );
    if (scanned == null || !mounted) return;

    final value = scanned.trim();
    if (_uuidRe.hasMatch(value)) {
      await _lookupAndJoin(value);
    } else {
      setState(() => _error = 'QR inválido. Escaneie o QR da assessoria.');
    }
  }

  Future<void> _enterCode() async {
    final codeCtrl = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Código da assessoria'),
        content: TextField(
          controller: codeCtrl,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Cole o código aqui',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, codeCtrl.text.trim()),
            child: const Text('Buscar'),
          ),
        ],
      ),
    );
    codeCtrl.dispose();
    if (code == null || code.isEmpty || !mounted) return;

    if (_uuidRe.hasMatch(code)) {
      await _lookupAndJoin(code);
    } else {
      setState(() => _error = 'Código inválido.');
    }
  }

  Future<void> _lookupAndJoin(String groupId) async {
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final res = await _client.rpc(
        'fn_search_coaching_groups',
        params: {'p_group_ids': [groupId]},
      );
      final list = res as List<dynamic>;
      if (list.isEmpty) {
        if (!mounted) return;
        setState(() {
          _busy = false;
          _error = 'Assessoria não encontrada.';
        });
        return;
      }
      final group = _GroupInfo.fromJson(list.first as Map<String, dynamic>);
      if (!mounted) return;
      setState(() => _busy = false);
      await _joinGroup(group.id, group.name);
    } catch (e) {
      AppLogger.error('Lookup failed: $e', tag: _tag, error: e);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Erro ao buscar assessoria.';
      });
    }
  }

  // ── Shared ───────────────────────────────────────────────────────────────

  Future<void> _setReady() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return;
    await _client.from('profiles').update({
      'onboarding_state': 'READY',
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', uid);
    AppLogger.info('onboarding_state → READY', tag: _tag);
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return switch (_mode) {
      _StaffMode.choose => _buildChoose(context),
      _StaffMode.create => _buildCreate(context),
      _StaffMode.join => _buildJoin(context),
    };
  }

  // ── Choose mode ──────────────────────────────────────────────────────────

  Widget _buildChoose(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            children: [
              if (widget.onBack != null) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: widget.onBack,
                    tooltip: 'Voltar para o login',
                  ),
                ),
              ],
              const Spacer(flex: 2),
              Text(
                'Monte sua\nassessoria',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  height: 1.3,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Escolha como começar.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const Spacer(),
              _OptionCard(
                icon: Icons.add_business_rounded,
                title: 'Criar assessoria',
                subtitle: 'Sou o responsável pela assessoria',
                color: primary,
                onTap: () => setState(() => _mode = _StaffMode.create),
              ),
              const SizedBox(height: 14),
              _OptionCard(
                icon: Icons.school_rounded,
                title: 'Entrar como professor',
                subtitle: 'Já tenho um convite ou código',
                color: primary,
                onTap: () => setState(() => _mode = _StaffMode.join),
              ),
              const Spacer(flex: 3),
            ],
          ),
        ),
      ),
    );
  }

  // ── Create mode ──────────────────────────────────────────────────────────

  Widget _buildCreate(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _busy
              ? null
              : () => setState(() {
                    _mode = _StaffMode.choose;
                    _error = null;
                  }),
        ),
        title: const Text('Criar assessoria'),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _nameCtrl,
              enabled: !_busy,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: 'Nome da assessoria *',
                hintText: 'Ex: Assessoria Velocidade',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _cityCtrl,
              enabled: !_busy,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: 'Cidade (opcional)',
                hintText: 'Ex: São Paulo',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Icon(Icons.error_outline,
                      size: 18, color: theme.colorScheme.error),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      _error!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const Spacer(),
            SizedBox(
              height: 56,
              child: FilledButton(
                onPressed: !_busy ? _createAssessoria : null,
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child: _busy
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Criar'),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  // ── Join mode ────────────────────────────────────────────────────────────

  Widget _buildJoin(BuildContext context) {
    final theme = Theme.of(context);
    final hasQuery = _searchCtrl.text.trim().length >= 2;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _busy
              ? null
              : () => setState(() {
                    _mode = _StaffMode.choose;
                    _error = null;
                    _results = [];
                    _searchCtrl.clear();
                  }),
        ),
        title: const Text('Entrar como professor'),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _searchCtrl,
              enabled: !_busy,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Buscar assessoria...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.qr_code_scanner_rounded),
                  tooltip: 'Escanear QR',
                  onPressed: _busy ? null : _scanQr,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _busy ? null : _enterCode,
                icon: const Icon(Icons.key_rounded, size: 18),
                label: const Text('Tenho um código'),
              ),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: _busy
                  ? const Center(child: CircularProgressIndicator())
                  : _searching
                      ? const Center(child: CircularProgressIndicator())
                      : _buildResults(theme, hasQuery),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline,
                      size: 18, color: theme.colorScheme.error),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      _error!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildResults(ThemeData theme, bool hasQuery) {
    if (!hasQuery && _results.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_rounded, size: 56, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text(
              'Digite o nome da assessoria\nou escaneie um QR',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    if (hasQuery && _results.isEmpty) {
      return Center(
        child: Text(
          'Nenhuma assessoria encontrada.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return ListView.builder(
      itemCount: _results.length,
      itemBuilder: (_, i) {
        final g = _results[i];
        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: 0,
          color: theme.colorScheme.surfaceContainerLow,
          child: ListTile(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            leading: CircleAvatar(
              backgroundColor: theme.colorScheme.primaryContainer,
              child: Icon(Icons.groups_rounded,
                  color: theme.colorScheme.onPrimaryContainer),
            ),
            title: Text(g.name,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(
              [if (g.city.isNotEmpty) g.city, '${g.memberCount} membros']
                  .join(' · '),
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => _joinGroup(g.id, g.name),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Option card (choose mode)
// ---------------------------------------------------------------------------

class _OptionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _OptionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade300),
          color: theme.colorScheme.surface,
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 28, color: color),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                color: theme.colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// QR Scanner page (shared with JoinAssessoriaScreen pattern)
// ---------------------------------------------------------------------------

class _QrScannerPage extends StatefulWidget {
  const _QrScannerPage();

  @override
  State<_QrScannerPage> createState() => _QrScannerPageState();
}

class _QrScannerPageState extends State<_QrScannerPage> {
  bool _scanned = false;

  void _onDetect(BarcodeCapture capture) {
    if (_scanned) return;
    final barcode = capture.barcodes.firstOrNull;
    if (barcode?.rawValue == null) return;
    _scanned = true;
    Navigator.of(context).pop(barcode!.rawValue);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Escanear QR')),
      body: MobileScanner(onDetect: _onDetect),
    );
  }
}
