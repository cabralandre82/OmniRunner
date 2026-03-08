import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:omni_runner/core/logging/logger.dart';

/// Global BlocObserver that logs transitions and errors.
///
/// Registered once in [main] via [Bloc.observer].
/// Keeps log volume low by only emitting on errors and
/// debug-level on transitions.
class AppBlocObserver extends BlocObserver {
  @override
  void onError(BlocBase<dynamic> bloc, Object error, StackTrace stackTrace) {
    AppLogger.error(
      '${bloc.runtimeType} error',
      tag: 'Bloc',
      error: error,
      stack: stackTrace,
    );
    super.onError(bloc, error, stackTrace);
  }

  @override
  void onTransition(
    Bloc<dynamic, dynamic> bloc,
    Transition<dynamic, dynamic> transition,
  ) {
    AppLogger.debug(
      '${bloc.runtimeType}: ${transition.currentState.runtimeType} → ${transition.nextState.runtimeType}',
      tag: 'Bloc',
    );
    super.onTransition(bloc, transition);
  }
}
