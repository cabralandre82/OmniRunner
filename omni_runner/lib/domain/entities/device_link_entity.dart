import 'package:equatable/equatable.dart';

enum DeviceProvider { garmin, apple, polar, suunto, trainingpeaks }

String deviceProviderToString(DeviceProvider p) => switch (p) {
      DeviceProvider.garmin => 'garmin',
      DeviceProvider.apple => 'apple',
      DeviceProvider.polar => 'polar',
      DeviceProvider.suunto => 'suunto',
      DeviceProvider.trainingpeaks => 'trainingpeaks',
    };

DeviceProvider deviceProviderFromString(String s) => switch (s) {
      'garmin' => DeviceProvider.garmin,
      'apple' => DeviceProvider.apple,
      'polar' => DeviceProvider.polar,
      'trainingpeaks' => DeviceProvider.trainingpeaks,
      _ => DeviceProvider.suunto,
    };

final class DeviceLinkEntity extends Equatable {
  final String id;
  final String groupId;
  final String athleteUserId;
  final DeviceProvider provider;
  final DateTime? expiresAt;
  final DateTime linkedAt;

  const DeviceLinkEntity({
    required this.id,
    required this.groupId,
    required this.athleteUserId,
    required this.provider,
    this.expiresAt,
    required this.linkedAt,
  });

  @override
  List<Object?> get props => [id, athleteUserId, provider];
}
