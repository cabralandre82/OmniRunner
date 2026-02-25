import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

/// Global banner that appears at the top of the screen when there is no
/// internet connection. Automatically hides when connectivity is restored.
///
/// Wrap any screen or the entire app shell with this widget to get
/// consistent offline feedback across the application.
class NoConnectionBanner extends StatefulWidget {
  final Widget child;

  const NoConnectionBanner({super.key, required this.child});

  @override
  State<NoConnectionBanner> createState() => _NoConnectionBannerState();
}

class _NoConnectionBannerState extends State<NoConnectionBanner> {
  final _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _sub;
  bool _offline = false;

  @override
  void initState() {
    super.initState();
    _checkInitial();
    _sub = _connectivity.onConnectivityChanged.listen(_onChanged);
  }

  Future<void> _checkInitial() async {
    try {
      final result = await _connectivity.checkConnectivity();
      if (mounted) {
        setState(() {
          _offline = result.every((r) => r == ConnectivityResult.none);
        });
      }
    } on Exception catch (_) {
      // Can't determine — assume connected.
    }
  }

  void _onChanged(List<ConnectivityResult> results) {
    if (!mounted) return;
    final nowOffline = results.every((r) => r == ConnectivityResult.none);
    if (nowOffline != _offline) {
      setState(() => _offline = nowOffline);
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          height: _offline ? null : 0,
          child: _offline
              ? MaterialBanner(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  backgroundColor: Colors.orange.shade800,
                  content: const Text(
                    'Sem conexão com a internet. '
                    'Alguns recursos podem não funcionar.',
                    style: TextStyle(color: Colors.white, fontSize: 13),
                  ),
                  leading:
                      const Icon(Icons.wifi_off, color: Colors.white, size: 20),
                  actions: const [SizedBox.shrink()],
                )
              : const SizedBox.shrink(),
        ),
        Expanded(child: widget.child),
      ],
    );
  }
}
