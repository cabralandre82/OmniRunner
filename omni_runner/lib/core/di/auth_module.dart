import 'package:get_it/get_it.dart';

import 'package:omni_runner/core/auth/auth_repository.dart';
import 'package:omni_runner/core/auth/i_auth_datasource.dart';
import 'package:omni_runner/core/auth/user_identity_provider.dart';
import 'package:omni_runner/core/config/app_config.dart';
import 'package:omni_runner/core/config/feature_flags.dart';
import 'package:omni_runner/core/deep_links/deep_link_handler.dart';
import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/data/datasources/mock_auth_datasource.dart';
import 'package:omni_runner/data/datasources/mock_profile_datasource.dart';
import 'package:omni_runner/data/datasources/remote_auth_datasource.dart';
import 'package:omni_runner/data/datasources/remote_profile_datasource.dart';
import 'package:omni_runner/data/repositories_impl/profile_repo.dart';
import 'package:omni_runner/domain/repositories/i_profile_repo.dart';

/// Registers auth-related services: DeepLinkHandler, Auth, UserIdentity, Profile.
Future<void> registerAuthModule(GetIt sl) async {
  sl.registerSingleton<DeepLinkHandler>(DeepLinkHandler());

  final IAuthDataSource authDs = AppConfig.isSupabaseReady
      ? RemoteAuthDataSource()
      : () {
          AppLogger.critical(
            'AUTH: Supabase not ready — using MockAuthDataSource. '
            'This should NEVER happen in production.',
          );
          return MockAuthDataSource();
        }();
  sl.registerSingleton<IAuthDataSource>(authDs);

  final authRepo = AuthRepository(datasource: authDs);
  sl.registerSingleton<AuthRepository>(authRepo);

  final userIdentity = UserIdentityProvider(authRepo: authRepo);
  try {
    await userIdentity.init();
  } catch (e) {
    AppLogger.error('UserIdentityProvider.init failed — continuing with anonymous identity', error: e);
  }
  sl.registerSingleton<UserIdentityProvider>(userIdentity);

  final featureFlags = FeatureFlagService(userId: userIdentity.userId);
  await featureFlags.load();
  featureFlags.startPeriodicRefresh();
  sl.registerSingleton<FeatureFlagService>(featureFlags);

  final IProfileRepo profileDs = AppConfig.isSupabaseReady
      ? RemoteProfileDataSource()
      : () {
          AppLogger.critical(
            'PROFILE: Supabase not ready — using MockProfileDataSource. '
            'This should NEVER happen in production.',
          );
          return MockProfileDataSource(identity: userIdentity);
        }();
  sl.registerLazySingleton<IProfileRepo>(
    () => ProfileRepo(datasource: profileDs),
  );
}
