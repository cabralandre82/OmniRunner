import 'package:flutter/material.dart';

import 'package:omni_runner/domain/entities/location_point_entity.dart';

/// Card displaying the latest GPS point data during debug tracking.
///
/// Shows lat, lng, altitude, accuracy, speed, bearing, and timestamp.
/// If [point] is null, shows a placeholder message.
///
/// Temporary debug widget. Will be replaced by real UI in Phase 04+.
class DebugGpsPointCard extends StatelessWidget {
  /// The latest GPS point to display. Null means no data yet.
  final LocationPointEntity? point;

  const DebugGpsPointCard({super.key, this.point});

  @override
  Widget build(BuildContext context) {
    if (point == null) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'No GPS data yet.\nStart tracking to see live data.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Colors.grey),
          ),
        ),
      );
    }

    final p = point!;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Last GPS Point',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const Divider(),
            _dataRow('Latitude', p.lat.toStringAsFixed(6)),
            _dataRow('Longitude', p.lng.toStringAsFixed(6)),
            _dataRow(
              'Altitude',
              p.alt != null ? '${p.alt!.toStringAsFixed(1)} m' : 'N/A',
            ),
            _dataRow(
              'Accuracy',
              p.accuracy != null
                  ? '${p.accuracy!.toStringAsFixed(1)} m'
                  : 'N/A',
            ),
            _dataRow(
              'Speed',
              p.speed != null
                  ? '${p.speed!.toStringAsFixed(2)} m/s'
                  : 'N/A',
            ),
            _dataRow(
              'Bearing',
              p.bearing != null
                  ? '${p.bearing!.toStringAsFixed(1)}°'
                  : 'N/A',
            ),
            _dataRow(
              'Timestamp',
              DateTime.fromMillisecondsSinceEpoch(
                p.timestampMs,
              ).toIso8601String(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dataRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          Text(value, style: const TextStyle(fontFamily: 'monospace')),
        ],
      ),
    );
  }
}
