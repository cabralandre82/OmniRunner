import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:omni_runner/core/logging/logger.dart';

const _tag = 'RunShareCard';

/// Renders a visually appealing run summary card and shares it as PNG.
///
/// Call [shareRunCard] to show an off-screen card, capture it to image,
/// and open the OS share sheet.
Future<void> shareRunCard(
  BuildContext context, {
  required double distanceKm,
  required String pace,
  required String duration,
  required String date,
  int? avgBpm,
  String? userName,
}) async {
  final cardKey = GlobalKey();

  // Build card in an overlay so it renders off-screen at fixed size
  final overlay = OverlayEntry(
    builder: (_) => Positioned(
      left: -2000,
      top: -2000,
      child: RepaintBoundary(
        key: cardKey,
        child: _ShareCardContent(
          distanceKm: distanceKm,
          pace: pace,
          duration: duration,
          date: date,
          avgBpm: avgBpm,
          userName: userName,
        ),
      ),
    ),
  );

  Overlay.of(context).insert(overlay);

  // Wait for layout + paint
  await Future<void>.delayed(const Duration(milliseconds: 200));

  try {
    final boundary =
        cardKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) {
      AppLogger.warn('Could not find render boundary', tag: _tag);
      return;
    }

    final image = await boundary.toImage(pixelRatio: 3.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) return;

    final bytes = byteData.buffer.asUint8List();

    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/omni_runner_corrida.png');
    await file.writeAsBytes(bytes);

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'image/png')],
        title: 'Minha corrida no Omni Runner',
      ),
    );

    AppLogger.info('Run card shared (${bytes.length} bytes)', tag: _tag);

    // Cleanup
    try {
      if (await file.exists()) await file.delete();
    } on Exception {
      // best-effort
    }
  } on Exception catch (e) {
    AppLogger.warn('Share card failed: $e', tag: _tag);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível compartilhar')),
      );
    }
  } finally {
    overlay.remove();
  }
}

/// The actual card content — 1080px wide for Instagram Stories compatibility.
class _ShareCardContent extends StatelessWidget {
  final double distanceKm;
  final String pace;
  final String duration;
  final String date;
  final int? avgBpm;
  final String? userName;

  const _ShareCardContent({
    required this.distanceKm,
    required this.pace,
    required this.duration,
    required this.date,
    this.avgBpm,
    this.userName,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 360,
      child: Material(
        color: Colors.transparent,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF1A237E),
                Color(0xFF4A148C),
                Color(0xFF880E4F),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.directions_run_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'OMNI RUNNER',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 2,
                          ),
                        ),
                        if (userName != null)
                          Text(
                            userName!,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                      ],
                    ),
                    const Spacer(),
                    Text(
                      date,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 28),

                // Distance (hero metric)
                Text(
                  distanceKm.toStringAsFixed(2),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 64,
                    fontWeight: FontWeight.w900,
                    height: 1.0,
                    letterSpacing: -2,
                  ),
                ),
                const Text(
                  'quilômetros',
                  style: TextStyle(
                    color: Colors.white60,
                    fontSize: 16,
                    fontWeight: FontWeight.w300,
                    letterSpacing: 3,
                  ),
                ),

                const SizedBox(height: 28),

                // Divider
                Container(
                  height: 1,
                  color: Colors.white.withValues(alpha: 0.15),
                ),

                const SizedBox(height: 20),

                // Secondary metrics
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _MetricColumn(label: 'PACE', value: pace, unit: '/km'),
                    Container(
                      width: 1,
                      height: 40,
                      color: Colors.white.withValues(alpha: 0.15),
                    ),
                    _MetricColumn(label: 'DURAÇÃO', value: duration, unit: ''),
                    if (avgBpm != null) ...[
                      Container(
                        width: 1,
                        height: 40,
                        color: Colors.white.withValues(alpha: 0.15),
                      ),
                      _MetricColumn(
                        label: 'FC MÉD',
                        value: '$avgBpm',
                        unit: 'bpm',
                      ),
                    ],
                  ],
                ),

                const SizedBox(height: 24),

                // Footer
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.verified_rounded,
                          color: Colors.greenAccent, size: 14),
                      SizedBox(width: 6),
                      Text(
                        'Corrida verificada pelo Omni Runner',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MetricColumn extends StatelessWidget {
  final String label;
  final String value;
  final String unit;

  const _MetricColumn({
    required this.label,
    required this.value,
    required this.unit,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 4),
        RichText(
          text: TextSpan(
            children: [
              TextSpan(
                text: value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (unit.isNotEmpty)
                TextSpan(
                  text: ' $unit',
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
