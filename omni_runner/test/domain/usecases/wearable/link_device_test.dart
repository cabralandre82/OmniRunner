import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/device_link_entity.dart';
import 'package:omni_runner/domain/entities/workout_execution_entity.dart';
import 'package:omni_runner/domain/repositories/i_wearable_repo.dart';
import 'package:omni_runner/domain/usecases/wearable/link_device.dart';

class _FakeWearableRepo implements IWearableRepo {
  final List<DeviceLinkEntity> links = [];
  int _seq = 0;

  @override
  Future<DeviceLinkEntity> linkDevice({
    required String groupId,
    required String provider,
    String? accessToken,
    String? refreshToken,
  }) async {
    final link = DeviceLinkEntity(
      id: 'link-${++_seq}',
      groupId: groupId,
      athleteUserId: 'current-user',
      provider: deviceProviderFromString(provider),
      linkedAt: DateTime.now(),
    );
    links.add(link);
    return link;
  }

  @override
  Future<void> unlinkDevice(String linkId) async {
    links.removeWhere((l) => l.id == linkId);
  }

  @override
  Future<List<DeviceLinkEntity>> listDeviceLinks(
      String athleteUserId) async {
    return links
        .where((l) => l.athleteUserId == athleteUserId)
        .toList();
  }

  @override
  Future<Map<String, dynamic>> generateWorkoutPayload(
          String assignmentId) async =>
      {};
  @override
  Future<WorkoutExecutionEntity> importExecution({
    String? assignmentId,
    required int durationSeconds,
    int? distanceMeters,
    int? avgPace,
    int? avgHr,
    int? maxHr,
    int? calories,
    String source = 'manual',
    String? providerActivityId,
  }) async =>
      throw UnimplementedError();
  @override
  Future<List<WorkoutExecutionEntity>> listExecutions({
    required String groupId,
    required String athleteUserId,
    int limit = 50,
  }) async =>
      [];
}

void main() {
  late _FakeWearableRepo repo;
  late LinkDevice usecase;

  setUp(() {
    repo = _FakeWearableRepo();
    usecase = LinkDevice(repo: repo);
  });

  test('links a device', () async {
    final link = await usecase.call(
      groupId: 'group-1',
      provider: 'garmin',
      accessToken: 'token-abc',
      refreshToken: 'refresh-xyz',
    );

    expect(link.groupId, 'group-1');
    expect(link.provider, DeviceProvider.garmin);
    expect(repo.links.length, 1);
  });

  test('links device without tokens', () async {
    final link = await usecase.call(
      groupId: 'group-1',
      provider: 'apple',
    );

    expect(link.provider, DeviceProvider.apple);
  });

  test('unlinks a device', () async {
    final link = await usecase.call(
      groupId: 'group-1',
      provider: 'polar',
    );
    expect(repo.links.length, 1);

    await usecase.unlink(link.id);
    expect(repo.links, isEmpty);
  });

  test('lists device links for an athlete', () async {
    await usecase.call(groupId: 'group-1', provider: 'garmin');
    await usecase.call(groupId: 'group-1', provider: 'apple');

    final result = await usecase.list('current-user');
    expect(result.length, 2);
  });

  test('list returns empty for athlete with no links', () async {
    final result = await usecase.list('unknown-user');
    expect(result, isEmpty);
  });
}
