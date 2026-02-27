import 'package:flutter/material.dart';

import 'package:omni_runner/core/tips/first_use_tips.dart';

/// A dismissible info banner shown only once per [tipKey].
///
/// After the user taps "Entendi", the tip is marked as seen via
/// [FirstUseTips] and won't appear again.
class ContextualTipBanner extends StatefulWidget {
  final TipKey tipKey;
  final String message;
  final IconData icon;
  final Color? color;

  const ContextualTipBanner({
    super.key,
    required this.tipKey,
    required this.message,
    this.icon = Icons.lightbulb_outline_rounded,
    this.color,
  });

  @override
  State<ContextualTipBanner> createState() => _ContextualTipBannerState();
}

class _ContextualTipBannerState extends State<ContextualTipBanner>
    with SingleTickerProviderStateMixin {
  bool _visible = false;
  late final AnimationController _animCtrl;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeInOut);
    _checkVisibility();
  }

  Future<void> _checkVisibility() async {
    final show = await FirstUseTips.shouldShow(widget.tipKey);
    if (show && mounted) {
      setState(() => _visible = true);
      _animCtrl.forward();
    }
  }

  Future<void> _dismiss() async {
    await _animCtrl.reverse();
    await FirstUseTips.markSeen(widget.tipKey);
    if (mounted) setState(() => _visible = false);
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final accent = widget.color ?? theme.colorScheme.primary;

    return FadeTransition(
      opacity: _fadeAnim,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: accent.withValues(alpha: 0.25),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(widget.icon, color: accent, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.message,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface,
                    height: 1.4,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              TextButton(
                onPressed: _dismiss,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 32),
                  foregroundColor: accent,
                ),
                child: const Text('Entendi'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
