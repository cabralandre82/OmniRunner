import 'package:flutter/material.dart';
import 'package:omni_runner/core/storage/preferences_keys.dart';
import 'package:omni_runner/core/theme/design_tokens.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A reusable tooltip overlay shown on first view of a widget.
///
/// Wraps [child] and shows a tooltip overlay on first display. Persists viewed
/// state via SharedPreferences so it won't show again. Use [tooltipId] to
/// uniquely identify each tooltip instance.
///
/// Example:
/// ```dart
/// OnboardingTooltip(
///   tooltipId: 'wallet_intro',
///   title: 'Carteira',
///   description: 'Aqui você gerencia seus OmniCoins e recompensas.',
///   child: WalletCard(...),
/// )
/// ```
class OnboardingTooltip extends StatefulWidget {
  const OnboardingTooltip({
    super.key,
    required this.tooltipId,
    required this.title,
    required this.description,
    required this.child,
    this.onComplete,
  });

  /// Unique identifier for this tooltip. Used to persist viewed state.
  final String tooltipId;

  /// Tooltip title.
  final String title;

  /// Tooltip description text.
  final String description;

  /// The widget to wrap and attach the tooltip to.
  final Widget child;

  /// Optional callback when the tooltip is dismissed (Entendi or Próximo).
  final VoidCallback? onComplete;

  @override
  State<OnboardingTooltip> createState() => _OnboardingTooltipState();
}

class _OnboardingTooltipState extends State<OnboardingTooltip>
    with SingleTickerProviderStateMixin {
  OverlayEntry? _overlayEntry;
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;

  static String _storageKey(String tooltipId) =>
      '${PreferencesKeys.onboardingTooltipPrefix}$tooltipId';

  Future<bool> _shouldShow() async {
    final prefs = await SharedPreferences.getInstance();
    return !(prefs.getBool(_storageKey(widget.tooltipId)) ?? false);
  }

  Future<void> _markViewed() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_storageKey(widget.tooltipId), true);
  }

  void _dismiss() {
    _markViewed();
    widget.onComplete?.call();
    _controller.reverse().then((_) {
      _overlayEntry?.remove();
      _overlayEntry = null;
    });
  }

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: DesignTokens.durationNormal,
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    );
    _checkAndShow();
  }

  Future<void> _checkAndShow() async {
    final shouldShow = await _shouldShow();
    if (!mounted) return;
    if (shouldShow) {
      _insertOverlay();
      _controller.forward();
    }
  }

  void _insertOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = OverlayEntry(
      builder: (context) => FadeTransition(
        opacity: _fadeAnimation,
        child: Material(
          color: Colors.transparent,
          child: GestureDetector(
            onTap: () {},
            behavior: HitTestBehavior.opaque,
            child: Stack(
              children: [
                Container(color: DesignTokens.overlay),
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: DesignTokens.spacingLg,
                    ),
                    child: _TooltipCard(
                      title: widget.title,
                      description: widget.description,
                      onGotIt: _dismiss,
                      onNext: _dismiss,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(_overlayEntry!);
  }

  @override
  void dispose() {
    _overlayEntry?.remove();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

class _TooltipCard extends StatelessWidget {
  const _TooltipCard({
    required this.title,
    required this.description,
    required this.onGotIt,
    required this.onNext,
  });

  final String title;
  final String description;
  final VoidCallback onGotIt;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 320),
      decoration: BoxDecoration(
        color: DesignTokens.surface,
        borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
        boxShadow: DesignTokens.shadowLg,
        border: Border.all(color: DesignTokens.border),
      ),
      padding: const EdgeInsets.all(DesignTokens.spacingMd),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: DesignTokens.titleMediumSize,
              fontWeight: DesignTokens.titleMediumWeight,
              color: DesignTokens.textPrimary,
            ),
          ),
          const SizedBox(height: DesignTokens.spacingSm),
          Text(
            description,
            style: const TextStyle(
              fontSize: DesignTokens.bodySize,
              color: DesignTokens.textSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: DesignTokens.spacingLg),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: onGotIt,
                child: const Text('Entendi'),
              ),
              const SizedBox(width: DesignTokens.spacingSm),
              FilledButton(
                onPressed: onNext,
                style: FilledButton.styleFrom(
                  backgroundColor: DesignTokens.primary,
                ),
                child: const Text('Próximo'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
