import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/core/storage/preferences_keys.dart';

/// Offline queue for failed RPC calls. Stores operations in SharedPreferences
/// and replays them when connectivity is restored.
///
/// Primary use case: workout execution logging (fn_import_execution, etc.).
/// Generic enough to handle any Supabase RPC.
class OfflineQueue {
  static const _maxRetryCount = 3;
  static const _maxAgeDays = 7;

  final SharedPreferences _prefs;
  final SupabaseClient _client;
  final Future<void> Function(String operation, Map<String, dynamic> params)?
      _rpcInvoker;

  const OfflineQueue({
    required SharedPreferences prefs,
    required SupabaseClient client,
    Future<void> Function(String operation, Map<String, dynamic> params)?
        rpcInvoker,
  })  : _prefs = prefs,
        _client = client,
        _rpcInvoker = rpcInvoker;

  Future<void> _callRpc(String operation, Map<String, dynamic> params) async {
    final invoker = _rpcInvoker;
    if (invoker != null) {
      await invoker(operation, params);
      return;
    }
    await _client.rpc(operation, params: params);
  }

  /// Enqueue a failed RPC call for later retry.
  /// Call this when an RPC fails due to network/connectivity issues.
  Future<void> enqueue(String operation, Map<String, dynamic> params) async {
    final items = await _loadItems();
    final entry = _QueueEntry(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      operation: operation,
      params: params,
      timestamp: DateTime.now().toUtc(),
      retryCount: 0,
    );
    items.add(entry);
    await _saveItems(items);
    AppLogger.info('OfflineQueue: enqueued $operation', tag: 'OfflineQueue');
  }

  /// Replay all queued items in order. Removes successfully replayed items.
  /// Skips items that exceed maxRetryCount or maxAge.
  Future<int> replay() async {
    final items = await _loadItems();
    if (items.isEmpty) return 0;

    final cutoff =
        DateTime.now().toUtc().subtract(const Duration(days: _maxAgeDays));
    final valid = items
        .where((e) =>
            e.retryCount < _maxRetryCount && e.timestamp.isAfter(cutoff))
        .toList();
    if (valid.isEmpty) {
      await _clearAll();
      return 0;
    }

    var replayed = 0;
    final remaining = <_QueueEntry>[];

    for (final entry in valid) {
      try {
        await _callRpc(entry.operation, entry.params);
        replayed++;
        AppLogger.info(
            'OfflineQueue: replayed ${entry.operation}', tag: 'OfflineQueue');
      } on Object catch (e, st) {
        AppLogger.error('OfflineQueue: replay failed for ${entry.operation}',
            error: e, stack: st);
        final updated = _QueueEntry(
          id: entry.id,
          operation: entry.operation,
          params: entry.params,
          timestamp: entry.timestamp,
          retryCount: entry.retryCount + 1,
        );
        if (updated.retryCount < _maxRetryCount) {
          remaining.add(updated);
        }
      }
    }

    await _saveItems(remaining);
    return replayed;
  }

  /// Manually trigger replay (e.g. from a retry button). Same as [replay].
  Future<int> replayNow() => replay();

  /// Number of items currently in the queue.
  Future<int> get length async {
    final items = await _loadItems();
    final cutoff =
        DateTime.now().toUtc().subtract(const Duration(days: _maxAgeDays));
    return items
        .where((e) =>
            e.retryCount < _maxRetryCount && e.timestamp.isAfter(cutoff))
        .length;
  }

  Future<List<_QueueEntry>> _loadItems() async {
    final jsonList = _prefs.getStringList(PreferencesKeys.offlineQueueItems);
    if (jsonList == null) return [];

    final items = <_QueueEntry>[];
    for (final json in jsonList) {
      try {
        final map = jsonDecode(json) as Map<String, dynamic>;
        items.add(_QueueEntry.fromJson(map));
      } on Object catch (_) {
        // Skip malformed entries
      }
    }
    return items;
  }

  Future<void> _saveItems(List<_QueueEntry> items) async {
    final jsonList = items.map((e) => jsonEncode(e.toJson())).toList();
    await _prefs.setStringList(PreferencesKeys.offlineQueueItems, jsonList);
  }

  Future<void> _clearAll() async {
    await _prefs.remove(PreferencesKeys.offlineQueueItems);
  }
}

class _QueueEntry {
  final String id;
  final String operation;
  final Map<String, dynamic> params;
  final DateTime timestamp;
  final int retryCount;

  _QueueEntry({
    required this.id,
    required this.operation,
    required this.params,
    required this.timestamp,
    required this.retryCount,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'operation': operation,
        'params': params,
        'timestamp': timestamp.toIso8601String(),
        'retryCount': retryCount,
      };

  factory _QueueEntry.fromJson(Map<String, dynamic> json) => _QueueEntry(
        id: json['id'] as String,
        operation: json['operation'] as String,
        params: Map<String, dynamic>.from(json['params'] as Map),
        timestamp: DateTime.parse(json['timestamp'] as String),
        retryCount: json['retryCount'] as int? ?? 0,
      );
}
