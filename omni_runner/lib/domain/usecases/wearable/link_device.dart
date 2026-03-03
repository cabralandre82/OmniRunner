import 'package:omni_runner/domain/entities/device_link_entity.dart';
import 'package:omni_runner/domain/repositories/i_wearable_repo.dart';

final class LinkDevice {
  final IWearableRepo _repo;

  const LinkDevice({required IWearableRepo repo}) : _repo = repo;

  Future<DeviceLinkEntity> call({
    required String groupId,
    required String provider,
    String? accessToken,
    String? refreshToken,
  }) {
    return _repo.linkDevice(
      groupId: groupId,
      provider: provider,
      accessToken: accessToken,
      refreshToken: refreshToken,
    );
  }

  Future<void> unlink(String linkId) => _repo.unlinkDevice(linkId);

  Future<List<DeviceLinkEntity>> list(String athleteUserId) =>
      _repo.listDeviceLinks(athleteUserId);
}
