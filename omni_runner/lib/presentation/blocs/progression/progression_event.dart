import 'package:equatable/equatable.dart';

sealed class ProgressionEvent extends Equatable {
  const ProgressionEvent();

  @override
  List<Object?> get props => [];
}

final class LoadProgression extends ProgressionEvent {
  final String userId;
  const LoadProgression(this.userId);

  @override
  List<Object?> get props => [userId];
}

final class RefreshProgression extends ProgressionEvent {
  const RefreshProgression();
}
