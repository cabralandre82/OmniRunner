import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Animated checkmark that scales up with a bounce.
class AnimatedCheckmark extends StatefulWidget {
  final double size;
  final Color color;
  final VoidCallback? onComplete;

  const AnimatedCheckmark({
    super.key,
    this.size = 80,
    this.color = Colors.green,
    this.onComplete,
  });

  @override
  State<AnimatedCheckmark> createState() => _AnimatedCheckmarkState();
}

class _AnimatedCheckmarkState extends State<AnimatedCheckmark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  late final Animation<double> _check;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _scale = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.0, 0.5, curve: Curves.elasticOut),
    );
    _check = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.3, 1.0, curve: Curves.easeOut),
    );
    _ctrl.forward().then((_) => widget.onComplete?.call());
    HapticFeedback.mediumImpact();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          color: widget.color,
          shape: BoxShape.circle,
        ),
        child: AnimatedBuilder(
          animation: _check,
          builder: (_, __) => CustomPaint(
            painter: _CheckPainter(progress: _check.value),
          ),
        ),
      ),
    );
  }
}

class _CheckPainter extends CustomPainter {
  final double progress;

  _CheckPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = size.width * 0.1
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final path = Path();
    final cx = size.width / 2;
    final cy = size.height / 2;

    final p1 = Offset(cx * 0.55, cy * 1.05);
    final p2 = Offset(cx * 0.85, cy * 1.35);
    final p3 = Offset(cx * 1.45, cy * 0.65);

    if (progress <= 0.5) {
      final t = progress / 0.5;
      path.moveTo(p1.dx, p1.dy);
      path.lineTo(
        p1.dx + (p2.dx - p1.dx) * t,
        p1.dy + (p2.dy - p1.dy) * t,
      );
    } else {
      final t = (progress - 0.5) / 0.5;
      path.moveTo(p1.dx, p1.dy);
      path.lineTo(p2.dx, p2.dy);
      path.lineTo(
        p2.dx + (p3.dx - p2.dx) * t,
        p2.dy + (p3.dy - p2.dy) * t,
      );
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_CheckPainter old) => old.progress != progress;
}

/// Lightweight confetti burst using pure Flutter CustomPainter.
class ConfettiBurst extends StatefulWidget {
  final int particleCount;

  const ConfettiBurst({super.key, this.particleCount = 40});

  @override
  State<ConfettiBurst> createState() => _ConfettiBurstState();
}

class _ConfettiBurstState extends State<ConfettiBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final List<_Particle> _particles;

  @override
  void initState() {
    super.initState();
    final rng = Random();
    _particles = List.generate(widget.particleCount, (_) => _Particle(rng));
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) => CustomPaint(
          size: Size.infinite,
          painter: _ConfettiPainter(
            particles: _particles,
            progress: _ctrl.value,
          ),
        ),
      ),
    );
  }
}

class _Particle {
  final double angle;
  final double speed;
  final double size;
  final Color color;
  final double rotationSpeed;

  _Particle(Random rng)
      : angle = rng.nextDouble() * 2 * pi,
        speed = 200 + rng.nextDouble() * 300,
        size = 4 + rng.nextDouble() * 6,
        color = [
          Colors.red,
          Colors.blue,
          Colors.green,
          Colors.orange,
          Colors.purple,
          Colors.yellow,
          Colors.pink,
          Colors.teal,
        ][rng.nextInt(8)],
        rotationSpeed = rng.nextDouble() * 4;
}

class _ConfettiPainter extends CustomPainter {
  final List<_Particle> particles;
  final double progress;

  _ConfettiPainter({required this.particles, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final opacity = (1.0 - progress).clamp(0.0, 1.0);

    for (final p in particles) {
      final gravity = 200 * progress * progress;
      final dx = cx + cos(p.angle) * p.speed * progress;
      final dy = cy + sin(p.angle) * p.speed * progress * 0.6 + gravity;

      final paint = Paint()..color = p.color.withValues(alpha: opacity);

      canvas.save();
      canvas.translate(dx, dy);
      canvas.rotate(p.rotationSpeed * progress * pi * 2);
      canvas.drawRect(
        Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size * 0.6),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.progress != progress;
}

/// Shows a full-screen success overlay with checkmark + confetti.
/// Auto-dismisses after [duration].
Future<void> showSuccessOverlay(
  BuildContext context, {
  String? message,
  Duration duration = const Duration(milliseconds: 1800),
}) {
  return showGeneralDialog(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (ctx, _, __) => _SuccessOverlayContent(
      message: message,
      duration: duration,
    ),
  );
}

class _SuccessOverlayContent extends StatefulWidget {
  final String? message;
  final Duration duration;

  const _SuccessOverlayContent({this.message, required this.duration});

  @override
  State<_SuccessOverlayContent> createState() => _SuccessOverlayContentState();
}

class _SuccessOverlayContentState extends State<_SuccessOverlayContent> {
  @override
  void initState() {
    super.initState();
    Future.delayed(widget.duration, () {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 200,
            height: 200,
            child: Stack(
              alignment: Alignment.center,
              children: [
                ConfettiBurst(),
                AnimatedCheckmark(size: 80),
              ],
            ),
          ),
          if (widget.message != null) ...[
            const SizedBox(height: 16),
            Text(
              widget.message!,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
                decoration: TextDecoration.none,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}
