import 'package:flutter/material.dart';
import 'package:omni_runner/domain/entities/location_rationale.dart';

/// Shows a rationale dialog explaining why background location is needed,
/// as required by Android 11+ before requesting ACCESS_BACKGROUND_LOCATION.
///
/// Returns `true` if the user tapped "Continuar", `false` otherwise.
Future<bool> showBackgroundLocationRationale(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.location_on_outlined, size: 40),
      title: const Text(LocationRationale.backgroundTitle),
      content: const Text(LocationRationale.backgroundBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text(LocationRationale.backgroundSkip),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text(LocationRationale.backgroundProceed),
        ),
      ],
    ),
  );
  return result ?? false;
}
