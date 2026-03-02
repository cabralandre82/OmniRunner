import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:omni_runner/core/analytics/product_event_tracker.dart';
import 'package:omni_runner/core/deep_links/deep_link_handler.dart';
import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/core/push/notification_rules_service.dart';
import 'package:omni_runner/core/service_locator.dart';

/// Onboarding screen for athletes to join a coaching group (assessoria).
///
/// Provides four entry paths:
///   1. Search by name (via `fn_search_coaching_groups` RPC)
///   2. Scan QR code containing a group UUID
///   3. Enter a group code (UUID) manually
///   4. Skip ("Continuar sem assessoria")
///
/// Joining uses `fn_switch_assessoria` RPC (creates membership + sets
/// `profiles.active_coaching_group_id`). After join or skip, sets
/// `onboarding_state` to READY and calls [onComplete].
class JoinAssessoriaScreen extends StatefulWidget {
  final VoidCallback onComplete;
  final VoidCallback? onBack;

  /// Optional pre-filled invite/group code (e.g. from a deep link).
  final String? initialCode;

  const JoinAssessoriaScreen({
    super.key,
    required this.onComplete,
    this.onBack,
    this.initialCode,
  });

  @override
  State<JoinAssessoriaScreen> createState() => _JoinAssessoriaScreenState();
}

// ---------------------------------------------------------------------------
// Lightweight models (private to this screen)
// ---------------------------------------------------------------------------

class _GroupInfo {
  final String id;
  final String name;
  final String? logoUrl;
  final String city;
  final String coachDisplayName;
  final int memberCount;

  const _GroupInfo({
    required this.id,
    required this.name,
    this.logoUrl,
    required this.city,
    required this.coachDisplayName,
    required this.memberCount,
  });

  factory _GroupInfo.fromJson(Map<String, dynamic> j) => _GroupInfo(
        id: j['id'] as String,
        name: j['name'] as String? ?? '',
        logoUrl: j['logo_url'] as String?,
        city: (j['city'] as String?) ?? '',
        coachDisplayName: (j['coach_display_name'] as String?) ?? 'Coach',
        memberCount: (j['member_count'] as num?)?.toInt() ?? 0,
      );
}

class _PendingInvite {
  final String inviteId;
  final String groupId;
  final _GroupInfo? group;

  const _PendingInvite({
    required this.inviteId,
    required this.groupId,
    this.group,
  });
}

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

class _JoinAssessoriaScreenState extends State<JoinAssessoriaScreen> {
  static const _tag = 'JoinAssessoria';
  static final _uuidRe = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    caseSensitive: false,
  );

  final _searchCtrl = TextEditingController();
  Timer? _debounce;

  List<_GroupInfo> _results = [];
  List<_PendingInvite> _invites = [];
  bool _loadingSearch = false;
  bool _loadingInvites = true;
  bool _joining = false;
  String? _error;

  SupabaseClient get _client => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _loadPendingInvites();
    if (widget.initialCode != null && widget.initialCode!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final code = widget.initialCode!.trim();
        if (_uuidRe.hasMatch(code)) {
          _lookupAndJoin(code);
        } else {
          _lookupByInviteCode(code);
        }
      });
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── Pending invites ──────────────────────────────────────────────────────

  Future<void> _loadPendingInvites() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) {
      setState(() => _loadingInvites = false);
      return;
    }

    try {
      final rows = await _client
          .from('coaching_invites')
          .select('id, group_id, status, expires_at_ms')
          .eq('invited_user_id', uid)
          .eq('status', 'pending');

      if (rows.isEmpty) {
        if (mounted) setState(() => _loadingInvites = false);
        return;
      }

      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final valid = (rows as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .where((r) => (r['expires_at_ms'] as num).toInt() > nowMs)
          .toList();

      if (valid.isEmpty) {
        if (mounted) setState(() => _loadingInvites = false);
        return;
      }

      final groupIds = valid.map((r) => r['group_id'] as String).toList();
      final groups = await _client.rpc(
        'fn_search_coaching_groups',
        params: {'p_group_ids': groupIds},
      );

      final groupMap = <String, _GroupInfo>{};
      for (final g in (groups as List<dynamic>)) {
        final info = _GroupInfo.fromJson(g as Map<String, dynamic>);
        groupMap[info.id] = info;
      }

      final invites = valid.map((r) {
        final gid = r['group_id'] as String;
        return _PendingInvite(
          inviteId: r['id'] as String,
          groupId: gid,
          group: groupMap[gid],
        );
      }).toList();

      if (mounted) {
        setState(() {
          _invites = invites;
          _loadingInvites = false;
        });
      }
    } catch (e) {
      AppLogger.error('Load invites failed: $e', tag: _tag, error: e);
      if (mounted) setState(() => _loadingInvites = false);
    }
  }

  // ── Search ───────────────────────────────────────────────────────────────

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    final trimmed = query.trim();
    if (trimmed.length < 2) {
      setState(() {
        _results = [];
        _loadingSearch = false;
      });
      return;
    }
    setState(() => _loadingSearch = true);
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
          _loadingSearch = false;
        });
      }
    } catch (e) {
      AppLogger.error('Search failed: $e', tag: _tag, error: e);
      if (mounted) {
        setState(() {
          _results = [];
          _loadingSearch = false;
        });
      }
    }
  }

  // ── Join / Skip ──────────────────────────────────────────────────────────

  Future<void> _joinGroup(String groupId, String groupName) async {
    // Check if there's an existing pending request for another group
    bool hasPendingElsewhere = false;
    try {
      final uid = _client.auth.currentUser?.id;
      if (uid != null) {
        final pending = await _client
            .from('coaching_join_requests')
            .select('group_id')
            .eq('user_id', uid)
            .eq('status', 'pending')
            .neq('group_id', groupId)
            .limit(1);
        hasPendingElsewhere = (pending as List).isNotEmpty;
      }
    } catch (e) {
      AppLogger.warn('Unexpected error', tag: 'JoinAssessoriaScreen', error: e);
    }

    if (!mounted) return;

    final message = hasPendingElsewhere
        ? 'Você já tem uma solicitação pendente em outra assessoria. '
          'Ao solicitar entrada em "$groupName", a solicitação anterior '
          'será cancelada automaticamente.'
        : 'Sua solicitação será enviada para a assessoria '
          '"$groupName". Você será adicionado quando a assessoria aprovar.';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Solicitar entrada?'),
        content: Text(message),
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
      _joining = true;
      _error = null;
    });

    try {
      final res = await _client.rpc(
        'fn_request_join',
        params: {'p_group_id': groupId},
      );
      final data = res as Map<String, dynamic>?;
      final status = data?['status'] as String?;

      if (status == 'already_member') {
        AppLogger.info('Already a member of $groupId', tag: _tag);
        await _setReady();
        if (!mounted) return;
        widget.onComplete();
        return;
      }

      if (status == 'already_requested') {
        if (!mounted) return;
        setState(() {
          _joining = false;
          _error = null;
        });
        _showRequestSent(groupName, alreadyExists: true);
        return;
      }

      final cancelled = (data?['cancelled_previous'] as num?)?.toInt() ?? 0;
      AppLogger.info(
        'Requested to join $groupId (cancelled $cancelled previous)',
        tag: _tag,
      );
      sl<ProductEventTracker>().track(ProductEvents.onboardingCompleted, {
        'role': 'ATLETA',
        'method': 'request_join',
      });

      // Push notification to staff (fire-and-forget)
      final displayName = Supabase.instance.client.auth.currentUser
              ?.userMetadata?['display_name'] as String? ??
          'Um atleta';
      sl<NotificationRulesService>().notifyJoinRequestReceived(
        groupId: groupId,
        athleteName: displayName,
      );

      await _setReady();
      if (!mounted) return;
      _showRequestSent(groupName, alreadyExists: false);
    } catch (e) {
      AppLogger.error('Join request failed: $e', tag: _tag, error: e);
      if (!mounted) return;
      setState(() {
        _joining = false;
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
                'Aguarde a aprovação da assessoria.'
              : 'Sua solicitação foi enviada para "$groupName". '
                'A assessoria irá analisar e aprovar sua entrada.',
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

  Future<void> _acceptInvite(_PendingInvite invite) async {
    setState(() {
      _joining = true;
      _error = null;
    });

    try {
      // Staff-originated invites bypass the approval flow
      await _client.rpc(
        'fn_switch_assessoria',
        params: {'p_new_group_id': invite.groupId},
      );

      await _client
          .from('coaching_invites')
          .update({'status': 'accepted'})
          .eq('id', invite.inviteId);

      AppLogger.info('Accepted invite ${invite.inviteId} → ${invite.groupId}',
          tag: _tag);
      await _setReady();
      sl<ProductEventTracker>().track(ProductEvents.onboardingCompleted, {
        'role': 'ATLETA',
        'method': 'accept_invite',
      });
      if (!mounted) return;
      widget.onComplete();
    } catch (e) {
      AppLogger.error('Accept invite failed: $e', tag: _tag, error: e);
      if (!mounted) return;
      setState(() {
        _joining = false;
        _error = 'Não foi possível aceitar o convite. Tente novamente.';
      });
    }
  }

  Future<void> _skip() async {
    setState(() {
      _joining = true;
      _error = null;
    });

    try {
      await _setReady();
      sl<ProductEventTracker>().track(ProductEvents.onboardingCompleted, {
        'role': 'ATLETA',
        'method': 'skip',
      });
      sl<ProductEventTracker>().track(ProductEvents.flowAbandoned, {
        'flow': 'onboarding',
        'step': 'join_assessoria',
        'reason': 'skipped',
      });
      if (!mounted) return;
      widget.onComplete();
    } catch (e) {
      AppLogger.error('Skip failed: $e', tag: _tag, error: e);
      if (!mounted) return;
      setState(() {
        _joining = false;
        _error = 'Erro ao continuar. Tente novamente.';
      });
    }
  }

  Future<void> _setReady() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return;
    await _client.from('profiles').update({
      'onboarding_state': 'READY',
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', uid);
    AppLogger.info('onboarding_state → READY', tag: _tag);
  }

  // ── QR Scanner ───────────────────────────────────────────────────────────

  Future<void> _scanQr() async {
    final scanned = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const _QrScannerPage()),
    );
    if (scanned == null || !mounted) return;

    final value = scanned.trim();

    // Try extracting an invite code from a URL or raw value
    final inviteCode = DeepLinkHandler.extractInviteCode(value);

    if (inviteCode != null && _uuidRe.hasMatch(inviteCode)) {
      await _lookupAndJoin(inviteCode);
    } else if (inviteCode != null) {
      await _lookupByInviteCode(inviteCode);
    } else {
      setState(() => _error = 'QR inválido. Escaneie o QR da assessoria.');
    }
  }

  // ── Code entry ───────────────────────────────────────────────────────────

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
      await _lookupByInviteCode(code);
    }
  }

  Future<void> _lookupByInviteCode(String code) async {
    setState(() {
      _joining = true;
      _error = null;
    });

    try {
      final res = await _client.rpc(
        'fn_lookup_group_by_invite_code',
        params: {'p_code': code},
      );
      final list = res as List<dynamic>;
      if (list.isEmpty) {
        if (!mounted) return;
        setState(() {
          _joining = false;
          _error = 'Código de convite inválido ou assessoria não aceita novos membros.';
        });
        return;
      }
      final group = _GroupInfo.fromJson(list.first as Map<String, dynamic>);
      if (!mounted) return;
      setState(() => _joining = false);
      await _joinGroup(group.id, group.name);
    } catch (e) {
      AppLogger.error('Invite code lookup failed: $e', tag: _tag, error: e);
      if (!mounted) return;
      setState(() {
        _joining = false;
        _error = 'Erro ao buscar assessoria pelo código de convite.';
      });
    }
  }

  Future<void> _lookupAndJoin(String groupId) async {
    setState(() {
      _joining = true;
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
          _joining = false;
          _error = 'Assessoria não encontrada.';
        });
        return;
      }
      final group = _GroupInfo.fromJson(list.first as Map<String, dynamic>);
      if (!mounted) return;
      setState(() => _joining = false);
      await _joinGroup(group.id, group.name);
    } catch (e) {
      AppLogger.error('Lookup failed: $e', tag: _tag, error: e);
      if (!mounted) return;
      setState(() {
        _joining = false;
        _error = 'Erro ao buscar assessoria.';
      });
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.onBack != null) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: _joining ? null : widget.onBack,
                    tooltip: 'Voltar para o login',
                  ),
                ),
              ] else
                const SizedBox(height: 40),

              // Header
              Text(
                'Encontre sua\nassessoria',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  height: 1.3,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Busque pelo nome, escaneie um QR ou use um código.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),

              // Search bar
              TextField(
                controller: _searchCtrl,
                enabled: !_joining,
                onChanged: _onSearchChanged,
                decoration: InputDecoration(
                  hintText: 'Buscar assessoria...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.qr_code_scanner_rounded),
                    tooltip: 'Escanear QR',
                    onPressed: _joining ? null : _scanQr,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // "Tenho um código" button
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _joining ? null : _enterCode,
                  icon: const Icon(Icons.key_rounded, size: 18),
                  label: const Text('Tenho um código'),
                ),
              ),
              const SizedBox(height: 4),

              // Results / invites list
              Expanded(child: _buildList(theme)),

              // Error display
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

              const SizedBox(height: 12),

              // Skip button
              SizedBox(
                width: double.infinity,
                height: 48,
                child: TextButton(
                  onPressed: _joining ? null : _skip,
                  child: _joining
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        )
                      : const Text('Pular — posso entrar depois'),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Você pode usar o app normalmente. Assessoria desbloqueia '
                'ranking de grupo e desafios em equipe.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildList(ThemeData theme) {
    if (_joining) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_loadingSearch) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.only(top: 32),
          child: CircularProgressIndicator(),
        ),
      );
    }

    final hasQuery = _searchCtrl.text.trim().length >= 2;
    final hasResults = _results.isNotEmpty;
    final hasInvites = _invites.isNotEmpty;

    if (!hasQuery && !hasInvites && !_loadingInvites) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.groups_outlined,
                size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text(
              'Digite o nome da assessoria\npara buscar',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return ListView(
      children: [
        // Pending invites
        if (hasInvites) ...[
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 8),
            child: Text(
              'Convites pendentes',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          for (final inv in _invites)
            _GroupTile(
              name: inv.group?.name ?? 'Assessoria',
              city: inv.group?.city ?? '',
              memberCount: inv.group?.memberCount ?? 0,
              coachName: inv.group?.coachDisplayName ?? '',
              trailing: FilledButton.tonal(
                onPressed: () => _acceptInvite(inv),
                child: const Text('Aceitar'),
              ),
            ),
          const Divider(height: 24),
        ],

        // Search results
        if (hasQuery && hasResults) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Resultados',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          for (final g in _results)
            _GroupTile(
              name: g.name,
              city: g.city,
              memberCount: g.memberCount,
              coachName: g.coachDisplayName,
              onTap: () => _joinGroup(g.id, g.name),
            ),
        ],

        if (hasQuery && !hasResults)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Center(
              child: Text(
                'Nenhuma assessoria encontrada.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Group tile
// ---------------------------------------------------------------------------

class _GroupTile extends StatelessWidget {
  final String name;
  final String city;
  final int memberCount;
  final String coachName;
  final VoidCallback? onTap;
  final Widget? trailing;

  const _GroupTile({
    required this.name,
    required this.city,
    required this.memberCount,
    required this.coachName,
    this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.groups_rounded,
                  size: 24,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        if (city.isNotEmpty) city,
                        '$memberCount membros',
                      ].join(' · '),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (trailing != null) trailing!,
              if (trailing == null)
                Icon(
                  Icons.chevron_right_rounded,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// QR Scanner page
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
