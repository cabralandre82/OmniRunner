// ignore_for_file: invalid_override, invalid_use_of_type_outside_library, extends_non_class, super_formal_parameter_without_associated_positional
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:omni_runner/core/config/feature_flags.dart';
import 'package:omni_runner/domain/entities/device_link_entity.dart';
import 'package:omni_runner/domain/usecases/wearable/link_device.dart';
import 'package:omni_runner/presentation/screens/athlete_device_link_screen.dart';

import '../../helpers/pump_app.dart';

final _sl = GetIt.instance;

class _FakeLinkDevice implements LinkDevice {
  @override
  Future<List<DeviceLinkEntity>> list(String athleteUserId) async => [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeFeatureFlags implements FeatureFlagService {
  @override
  bool isEnabled(String key) => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('AthleteDeviceLinkScreen', () {
    final origOnError = FlutterError.onError;

    setUp(() {
      FlutterError.onError = (details) {
        final msg = details.exceptionAsString();
        if (msg.contains('overflowed')) return;
        origOnError?.call(details);
      };
      _sl.registerFactory<LinkDevice>(() => _FakeLinkDevice());
      _sl.registerFactory<FeatureFlagService>(() => _FakeFeatureFlags());
    });
    tearDown(() {
      FlutterError.onError = origOnError;
      _sl.reset();
    });

    testWidgets('renders without crash', (tester) async {
      await tester.pumpApp(
        const AthleteDeviceLinkScreen(
          athleteUserId: 'u1',
          groupId: 'g1',
        ),
        wrapScaffold: false,
      );

      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('shows AppBar', (tester) async {
      await tester.pumpApp(
        const AthleteDeviceLinkScreen(
          athleteUserId: 'u1',
          groupId: 'g1',
        ),
        wrapScaffold: false,
      );

      expect(find.byType(AppBar), findsOneWidget);
    });
  });
}
