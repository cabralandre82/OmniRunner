import 'package:omni_runner/core/logging/logger.dart';

/// Safe alternative to [EnumName.byName] that returns a fallback instead of
/// throwing [ArgumentError] on unknown/corrupted values.
T safeByName<T extends Enum>(
  List<T> values,
  String name, {
  required T fallback,
}) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  AppLogger.warn(
    'Unknown enum value "$name" for ${T.toString()}, using fallback "${fallback.name}"',
    tag: 'safeByName',
  );
  return fallback;
}
