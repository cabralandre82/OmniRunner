import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/core/errors/coaching_failures.dart';
import 'package:omni_runner/domain/repositories/i_switch_assessoria_repo.dart';
import 'package:omni_runner/domain/usecases/coaching/switch_assessoria.dart';

class _FakeRepo implements ISwitchAssessoriaRepo {
  String? result;
  @override
  Future<String> switchTo(String newGroupId) async {
    if (result != null) return result!;
    throw SwitchAssessoriaFailed(newGroupId, 'server error');
  }
}

void main() {
  test('delegates to repo and returns new group id', () async {
    final repo = _FakeRepo()..result = 'g2';
    final usecase = SwitchAssessoria(repo: repo);
    final id = await usecase.call('g2');
    expect(id, 'g2');
  });

  test('throws SwitchAssessoriaFailed on error', () {
    final repo = _FakeRepo();
    final usecase = SwitchAssessoria(repo: repo);
    expect(() => usecase.call('g2'), throwsA(isA<SwitchAssessoriaFailed>()));
  });
}
