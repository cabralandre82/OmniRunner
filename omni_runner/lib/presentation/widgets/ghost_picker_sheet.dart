import 'package:flutter/material.dart';

import 'package:omni_runner/domain/entities/workout_session_entity.dart';

/// Bottom sheet listing completed sessions for ghost selection.
///
/// Returns the selected [WorkoutSessionEntity] via `Navigator.pop`.
class GhostPickerSheet extends StatelessWidget {
  final List<WorkoutSessionEntity> sessions;
  const GhostPickerSheet({super.key, required this.sessions});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Escolher corrida fantasma',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
        const Divider(height: 1),
        ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.4,
          ),
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: sessions.length,
            itemBuilder: (_, i) {
              final s = sessions[i];
              final d = DateTime.fromMillisecondsSinceEpoch(s.startTimeMs);
              final date =
                  '${d.day}/${d.month}/${d.year} '
                  '${d.hour}:${d.minute.toString().padLeft(2, '0')}';
              final dist = s.totalDistanceM != null && s.totalDistanceM! > 0
                  ? '${(s.totalDistanceM! / 1000).toStringAsFixed(2)} km'
                  : '--';
              return ListTile(
                leading: const Icon(Icons.directions_run, color: Colors.purple),
                title: Text(date),
                subtitle: Text(dist),
                onTap: () => Navigator.of(context).pop(s),
              );
            },
          ),
        ),
      ],),
    );
  }
}
