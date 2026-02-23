import 'package:flutter/material.dart';

import 'package:omni_runner/core/tips/first_use_tips.dart';

/// A dismissible contextual tip banner shown once per [tipKey].
///
/// Automatically checks [FirstUseTips.shouldShow] and hides itself
/// after being dismissed. The banner won't reappear after dismissal.
class TipBanner extends StatefulWidget {
  final TipKey tipKey;
  final IconData icon;
  final String text;

  const TipBanner({
    super.key,
    required this.tipKey,
    required this.icon,
    required this.text,
  });

  @override
  State<TipBanner> createState() => _TipBannerState();
}

class _TipBannerState extends State<TipBanner>
    with SingleTickerProviderStateMixin {
  bool _visible = false;
  late final AnimationController _anim;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _fade = CurvedAnimation(parent: _anim, curve: Curves.easeInOut);
    _check();
  }

  Future<void> _check() async {
    final show = await FirstUseTips.shouldShow(widget.tipKey);
    if (show && mounted) {
      setState(() => _visible = true);
      _anim.forward();
    }
  }

  Future<void> _dismiss() async {
    await _anim.reverse();
    await FirstUseTips.markSeen(widget.tipKey);
    if (mounted) setState(() => _visible = false);
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();

    final theme = Theme.of(context);

    return FadeTransition(
      opacity: _fade,
      child: SizeTransition(
        sizeFactor: _fade,
        axisAlignment: -1,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(widget.icon,
                  size: 22, color: theme.colorScheme.onPrimaryContainer),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.text,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                    height: 1.4,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: _dismiss,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                  minWidth: 32,
                  minHeight: 32,
                ),
                color: theme.colorScheme.onPrimaryContainer.withValues(
                  alpha: 0.6,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
