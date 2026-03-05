import 'dart:async';
import 'dart:ui';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:omni_runner/l10n/app_localizations.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:omni_runner/core/config/app_config.dart';
import 'package:omni_runner/core/deep_links/deep_link_handler.dart';
import 'package:omni_runner/core/offline/connectivity_monitor.dart';
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

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    AppLogger.error(
      'FlutterError',
      tag: 'ErrorHandler',
      error: details.exception,
      stack: details.stack,
    );
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    AppLogger.error('PlatformError', tag: 'ErrorHandler', error: error, stack: stack);
    return true;
  };

  ErrorWidget.builder = (details) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.red),
                const SizedBox(height: 16),
                const Text('Algo deu errado', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                const Text('Tente reiniciar o aplicativo.', textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      ),
    );
  };

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
    runZonedGuarded(
      () async => await _bootstrap(),
      (error, stack) {
        AppLogger.error('Uncaught error', tag: 'ErrorHandler', error: error, stack: stack);
      },
    );
  }
}

Future<void> _bootstrap() async {
  RecoveredSession? recovery;

  try {
    await _initServices();
    recovery = await sl<RecoverActiveSession>()();
  } catch (e, stack) {
    AppLogger.error(
      'Bootstrap failed — launching with fallback UI',
      tag: 'Main',
      error: e,
      stack: stack,
    );
  }

  runApp(OmniRunnerApp(recovery: recovery));
}

Future<void> _initServices() async {
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

  if (AppConfig.isProd) {
    AppLogger.minLevel = LogLevel.info;
  }

  if (AppConfig.isSentryConfigured) {
    AppLogger.onError = (message, error, stack) {
      Sentry.captureException(error ?? message, stackTrace: stack);
    };
    AppLogger.info('Sentry initialized', tag: 'Main');
  }

  try {
    await Firebase.initializeApp();
    AppLogger.info('Firebase initialized', tag: 'Main');
  } on Exception catch (e) {
    AppLogger.warn('Firebase init failed — push disabled: $e', tag: 'Main');
  }

  await setupServiceLocator();

  try {
    await sl<DeepLinkHandler>().init();
  } catch (e) {
    AppLogger.warn('DeepLinkHandler init failed: $e', tag: 'Main');
  }

  try {
    ForegroundTaskConfig.init();
  } catch (e) {
    AppLogger.warn('ForegroundTaskConfig init failed: $e', tag: 'Main');
  }

  try {
    initWatchBridge();
  } catch (e) {
    AppLogger.warn('WatchBridge init failed: $e', tag: 'Main');
  }

  if (AppConfig.isSupabaseReady) {
    try {
      final pushService = sl<PushNotificationService>();
      final pushNav = PushNavigationHandler(navigatorKey: _navigatorKey);
      pushService.onForegroundMessage = pushNav.showForegroundBanner;
      await pushService.init();
      await pushNav.init();
    } catch (e) {
      AppLogger.warn('Push init failed: $e', tag: 'Main');
    }
  }

  try {
    final autoSync = AutoSyncManager(syncRepo: sl<ISyncRepo>());
    await autoSync.init();
  } catch (e) {
    AppLogger.warn('AutoSync init failed: $e', tag: 'Main');
  }

  if (AppConfig.isSupabaseReady) {
    try {
      sl<ConnectivityMonitor>().start();
    } catch (_) {}
  }

  try {
    await themeNotifier.load();
  } catch (e) {
    AppLogger.warn('Theme load failed: $e', tag: 'Main');
  }
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
        builder: (context, child) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
            systemNavigationBarColor: isDark ? Colors.black : Colors.white,
            systemNavigationBarIconBrightness:
                isDark ? Brightness.light : Brightness.dark,
          ));
          return MediaQuery(
            data: MediaQuery.of(context).removePadding(removeBottom: true),
            child: Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).padding.bottom,
              ),
              child: child!,
            ),
          );
        },
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
