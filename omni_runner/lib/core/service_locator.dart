/// Dependency Injection container using GetIt (Service Locator pattern).
///
/// Registration order: Infrastructure → Auth → Data → Presentation.
/// Each layer depends only on abstractions from the layer above (Clean Architecture).
///
/// - [registerSingleton]: single instance, created immediately
/// - [registerLazySingleton]: single instance, created on first access
/// - [registerFactory]: new instance on every access (BLoCs, stateful use cases)
///
/// Call [setupServiceLocator] once from `main.dart` before `runApp`.
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:omni_runner/core/config/app_config.dart';
import 'package:omni_runner/core/di/auth_module.dart';
import 'package:omni_runner/core/di/data_module.dart';
import 'package:omni_runner/core/di/presentation_module.dart';

final GetIt sl = GetIt.instance;

Future<void> setupServiceLocator() async {
  // --- Core infrastructure (required by all modules) ---
  final prefs = await SharedPreferences.getInstance();
  sl.registerSingleton<SharedPreferences>(prefs);

  if (AppConfig.isSupabaseReady) {
    sl.registerLazySingleton<SupabaseClient>(
      () => Supabase.instance.client,
    );
  }

  // --- Auth: DeepLink, Auth, UserIdentity, Profile ---
  await registerAuthModule(sl);

  // --- Data: Datasources, Repositories, Use Cases ---
  await registerDataModule(sl);

  // --- Presentation: BLoCs and remote sources ---
  registerPresentationModule(sl);
}
