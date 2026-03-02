import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:omni_runner/l10n/app_localizations.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:omni_runner/core/config/app_config.dart';
import 'package:omni_runner/core/deep_links/deep_link_handler.dart';
import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/core/push/push_navigation_handler.dart';
import 'package:omni_runner/core/push/push_notification_service.dart';
import 'package:omni_runner/core/service_locator.dart';
import 'package:omni_runner/core/sync/auto_sync_manager.dart';
import 'package:omni_runner/data/datasources/foreground_task_config.dart';
import 'package:omni_runner/domain/repositories/i_sync_repo.dart';
import 'package:omni_runner/features/watch_bridge/watch_bridge_init.dart';
import 'package:omni_runner/domain/usecases/discard_session.dart';
import 'package:omni_runner/domain/usecases/finish_session.dart';
import 'package:omni_runner/domain/usecases/recover_active_session.dart';
import 'package:omni_runner/core/theme/app_theme.dart';
import 'package:omni_runner/core/theme/theme_notifier.dart';
import 'package:omni_runner/presentation/screens/auth_gate.dart';
import 'package:omni_runner/presentation/screens/recovery_screen.dart';

final themeNotifier = ThemeNotifier();
final _navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (AppConfig.isSentryConfigured) {
    await SentryFlutter.init(
      (options) {
        options.dsn = AppConfig.sentryDsn;
        options.environment = AppConfig.sentryEnvironment;
        options.tracesSampleRate = AppConfig.isProd ? 0.2 : 1.0;
      },
      appRunner: _bootstrap,
    );
  } else {
    await _bootstrap();
  }
}

Future<void> _bootstrap() async {
  // Initialize Supabase only when both env vars are present and non-empty.
  if (AppConfig.isSupabaseConfigured) {
    try {
      await Supabase.initialize(
        url: AppConfig.supabaseUrl,
        anonKey: AppConfig.supabaseAnonKey,
      );
      AppConfig.markSupabaseReady();
    } on Exception catch (e) {
      AppLogger.error(
        'Supabase.initialize() failed: $e',
        tag: 'Main',
        error: e,
      );
    }
  }
  AppLogger.info('backendMode=${AppConfig.backendMode}', tag: 'Main');

  if (!AppConfig.isSupabaseReady && AppConfig.isSupabaseConfigured) {
    AppLogger.warn(
      'Supabase configured but failed to initialize — will show welcome screen',
      tag: 'Main',
    );
  }

  // Set logger minimum level for production builds.
  if (AppConfig.isProd) {
    AppLogger.minLevel = LogLevel.info;
  }

  // Connect AppLogger.error → Sentry for crash reporting.
  if (AppConfig.isSentryConfigured) {
    AppLogger.onError = (message, error, stack) {
      Sentry.captureException(error ?? message, stackTrace: stack);
    };
    AppLogger.info('Sentry initialized', tag: 'Main');
  }

  // Initialize Firebase for push notifications (FCM/APNS).
  try {
    await Firebase.initializeApp();
    AppLogger.info('Firebase initialized', tag: 'Main');
  } on Exception catch (e) {
    AppLogger.warn('Firebase init failed — push disabled: $e', tag: 'Main');
  }

  await setupServiceLocator();
  await sl<DeepLinkHandler>().init();
  ForegroundTaskConfig.init();
  initWatchBridge();

  // Initialize push notifications (requires Firebase + Supabase).
  if (AppConfig.isSupabaseReady) {
    final pushService = sl<PushNotificationService>();
    final pushNav = PushNavigationHandler(navigatorKey: _navigatorKey);

    pushService.onForegroundMessage = pushNav.showForegroundBanner;
    await pushService.init();
    await pushNav.init();
  }

  // Auto-sync pending sessions on startup and when connectivity restores.
  final autoSync = AutoSyncManager(syncRepo: sl<ISyncRepo>());
  await autoSync.init();

  await themeNotifier.load();

  // Check for an active session to recover.
  final recovery = await sl<RecoverActiveSession>()();

  runApp(OmniRunnerApp(recovery: recovery));
}

class OmniRunnerApp extends StatelessWidget {
  final RecoveredSession? recovery;

  const OmniRunnerApp({super.key, this.recovery});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (_, mode, __) => MaterialApp(
        navigatorKey: _navigatorKey,
        title: 'Omni Runner',
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: mode,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: recovery != null
            ? _RecoveryWrapper(recovery: recovery!)
            : const AuthGate(),
      ),
    );
  }
}

/// Stateful wrapper to handle resume/discard navigation.
class _RecoveryWrapper extends StatelessWidget {
  final RecoveredSession recovery;
  const _RecoveryWrapper({required this.recovery});

  @override
  Widget build(BuildContext context) {
    return RecoveryScreen(
      recovery: recovery,
      onResume: () { _finishAndNavigate(context); },
      onDiscard: () => _discardAndNavigate(context),
    );
  }

  Future<void> _finishAndNavigate(BuildContext context) async {
    await sl<FinishSession>()(sessionId: recovery.session.id);
    if (!context.mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => const AuthGate(),
      ),
    );
  }

  Future<void> _discardAndNavigate(BuildContext context) async {
    await sl<DiscardSession>()(recovery.session.id);

    if (context.mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => const AuthGate(),
        ),
      );
    }
  }
}
