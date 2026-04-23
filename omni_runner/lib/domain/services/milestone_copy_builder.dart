import 'package:omni_runner/domain/entities/milestone_entity.dart';
import 'package:omni_runner/domain/value_objects/audio_coach_locale.dart';
import 'package:omni_runner/domain/value_objects/milestone_kind.dart';

/// Locale-aware celebratory copy for [MilestoneEntity]s.
///
/// Pure, stateless. The presentation layer consumes the returned
/// [MilestoneCopy] to render the overlay (confetti + checkmark
/// already exist in `success_overlay.dart`; this builder only
/// produces the text strings).
///
/// Reuses [AudioCoachLocale] — the sender-side locale used by the
/// audio coach and the challenge invite — so the amateur's entire
/// emotional surface flows through a single set of 3 languages.
///
/// Finding reference: L22-09.
class MilestoneCopyBuilder {
  final AudioCoachLocale locale;

  const MilestoneCopyBuilder({this.locale = AudioCoachLocale.ptBR});

  MilestoneCopy build(MilestoneEntity m) {
    switch (locale) {
      case AudioCoachLocale.ptBR:
        return _ptBR(m);
      case AudioCoachLocale.en:
        return _en(m);
      case AudioCoachLocale.es:
        return _es(m);
    }
  }

  MilestoneCopy _ptBR(MilestoneEntity m) {
    switch (m.kind) {
      case MilestoneKind.firstRun:
        return const MilestoneCopy(
          title: 'Primeira corrida concluída! 🎉',
          subtitle: 'Você é oficialmente runner.',
          shareText: 'Acabei de completar minha primeira corrida no Omni Runner!',
        );
      case MilestoneKind.firstFiveK:
        return MilestoneCopy(
          title: 'Primeira 5K! 🏃‍♂️',
          subtitle: 'Você correu ${_km(m.triggerDistanceM)} — bem vindo ao clube.',
          shareText:
              'Completei minha primeira corrida de 5 km no Omni Runner! 🏃‍♂️',
        );
      case MilestoneKind.firstTenK:
        return MilestoneCopy(
          title: 'Primeira 10K! 🔥',
          subtitle: '${_km(m.triggerDistanceM)} de puro progresso.',
          shareText:
              'Completei minha primeira corrida de 10 km no Omni Runner! 🔥',
        );
      case MilestoneKind.firstHalfMarathon:
        return MilestoneCopy(
          title: 'Primeira meia maratona! 🏅',
          subtitle: '${_km(m.triggerDistanceM)} — você é outro nível.',
          shareText:
              'Terminei minha primeira meia maratona no Omni Runner! 🏅',
        );
      case MilestoneKind.firstMarathon:
        return MilestoneCopy(
          title: 'Primeira maratona! 🏆',
          subtitle: '${_km(m.triggerDistanceM)} — hall da fama.',
          shareText: 'Terminei minha primeira maratona no Omni Runner! 🏆',
        );
      case MilestoneKind.firstWeek:
        return MilestoneCopy(
          title: 'Primeira semana completa! 📆',
          subtitle:
              '${m.triggerCount ?? 3} corridas verificadas em 7 dias. Consistência é tudo.',
          shareText:
              'Completei minha primeira semana de treinos no Omni Runner! 📆',
        );
      case MilestoneKind.streakSeven:
        return const MilestoneCopy(
          title: 'Streak de 7 dias! 🔥',
          subtitle: 'Uma semana inteira rodando. Mantém o ritmo.',
          shareText: 'Streak de 7 dias no Omni Runner! 🔥',
        );
      case MilestoneKind.streakThirty:
        return const MilestoneCopy(
          title: 'Streak de 30 dias! 👑',
          subtitle: 'Um mês inteiro. Você é máquina.',
          shareText: 'Streak de 30 dias no Omni Runner! 👑',
        );
      case MilestoneKind.longestRunEver:
        return MilestoneCopy(
          title: 'Nova melhor marca! 📈',
          subtitle: '${_km(m.triggerDistanceM)} é sua nova distância recorde.',
          shareText:
              'Novo recorde pessoal: ${_km(m.triggerDistanceM)} no Omni Runner! 📈',
        );
    }
  }

  MilestoneCopy _en(MilestoneEntity m) {
    switch (m.kind) {
      case MilestoneKind.firstRun:
        return const MilestoneCopy(
          title: 'First run done! 🎉',
          subtitle: "You're officially a runner.",
          shareText: 'Just completed my first run on Omni Runner!',
        );
      case MilestoneKind.firstFiveK:
        return MilestoneCopy(
          title: 'First 5K! 🏃‍♂️',
          subtitle: 'You ran ${_km(m.triggerDistanceM)} — welcome to the club.',
          shareText: 'Completed my first 5 km run on Omni Runner! 🏃‍♂️',
        );
      case MilestoneKind.firstTenK:
        return MilestoneCopy(
          title: 'First 10K! 🔥',
          subtitle: '${_km(m.triggerDistanceM)} of pure progress.',
          shareText: 'Completed my first 10 km run on Omni Runner! 🔥',
        );
      case MilestoneKind.firstHalfMarathon:
        return MilestoneCopy(
          title: 'First half-marathon! 🏅',
          subtitle: '${_km(m.triggerDistanceM)} — next level.',
          shareText: 'Finished my first half-marathon on Omni Runner! 🏅',
        );
      case MilestoneKind.firstMarathon:
        return MilestoneCopy(
          title: 'First marathon! 🏆',
          subtitle: '${_km(m.triggerDistanceM)} — hall of fame.',
          shareText: 'Finished my first marathon on Omni Runner! 🏆',
        );
      case MilestoneKind.firstWeek:
        return MilestoneCopy(
          title: 'First full week! 📆',
          subtitle:
              '${m.triggerCount ?? 3} verified runs in 7 days. Consistency is everything.',
          shareText: 'Completed my first training week on Omni Runner! 📆',
        );
      case MilestoneKind.streakSeven:
        return const MilestoneCopy(
          title: '7-day streak! 🔥',
          subtitle: 'A full week running. Keep the rhythm.',
          shareText: '7-day streak on Omni Runner! 🔥',
        );
      case MilestoneKind.streakThirty:
        return const MilestoneCopy(
          title: '30-day streak! 👑',
          subtitle: 'A whole month. You are a machine.',
          shareText: '30-day streak on Omni Runner! 👑',
        );
      case MilestoneKind.longestRunEver:
        return MilestoneCopy(
          title: 'New personal best! 📈',
          subtitle: '${_km(m.triggerDistanceM)} is your new record distance.',
          shareText:
              'New personal best: ${_km(m.triggerDistanceM)} on Omni Runner! 📈',
        );
    }
  }

  MilestoneCopy _es(MilestoneEntity m) {
    switch (m.kind) {
      case MilestoneKind.firstRun:
        return const MilestoneCopy(
          title: '¡Primera carrera completada! 🎉',
          subtitle: 'Ahora eres runner.',
          shareText: '¡Completé mi primera carrera en Omni Runner!',
        );
      case MilestoneKind.firstFiveK:
        return MilestoneCopy(
          title: '¡Primeros 5K! 🏃‍♂️',
          subtitle:
              'Corriste ${_km(m.triggerDistanceM)} — bienvenido al club.',
          shareText: '¡Completé mi primer 5K en Omni Runner! 🏃‍♂️',
        );
      case MilestoneKind.firstTenK:
        return MilestoneCopy(
          title: '¡Primeros 10K! 🔥',
          subtitle: '${_km(m.triggerDistanceM)} de puro progreso.',
          shareText: '¡Completé mi primer 10K en Omni Runner! 🔥',
        );
      case MilestoneKind.firstHalfMarathon:
        return MilestoneCopy(
          title: '¡Primera media maratón! 🏅',
          subtitle: '${_km(m.triggerDistanceM)} — otro nivel.',
          shareText: '¡Terminé mi primera media maratón en Omni Runner! 🏅',
        );
      case MilestoneKind.firstMarathon:
        return MilestoneCopy(
          title: '¡Primera maratón! 🏆',
          subtitle: '${_km(m.triggerDistanceM)} — salón de la fama.',
          shareText: '¡Terminé mi primera maratón en Omni Runner! 🏆',
        );
      case MilestoneKind.firstWeek:
        return MilestoneCopy(
          title: '¡Primera semana completa! 📆',
          subtitle:
              '${m.triggerCount ?? 3} carreras verificadas en 7 días. La constancia lo es todo.',
          shareText:
              '¡Completé mi primera semana de entrenos en Omni Runner! 📆',
        );
      case MilestoneKind.streakSeven:
        return const MilestoneCopy(
          title: '¡Racha de 7 días! 🔥',
          subtitle: 'Una semana completa. Mantén el ritmo.',
          shareText: '¡Racha de 7 días en Omni Runner! 🔥',
        );
      case MilestoneKind.streakThirty:
        return const MilestoneCopy(
          title: '¡Racha de 30 días! 👑',
          subtitle: 'Un mes entero. Eres una máquina.',
          shareText: '¡Racha de 30 días en Omni Runner! 👑',
        );
      case MilestoneKind.longestRunEver:
        return MilestoneCopy(
          title: '¡Nuevo récord personal! 📈',
          subtitle: '${_km(m.triggerDistanceM)} es tu nueva distancia récord.',
          shareText:
              '¡Nuevo récord personal: ${_km(m.triggerDistanceM)} en Omni Runner! 📈',
        );
    }
  }

  static String _km(double? meters) {
    if (meters == null) return '';
    return '${(meters / 1000).toStringAsFixed(2)} km';
  }

  /// Kinds that this builder must cover in every supported
  /// locale. Mirrored in `tools/audit/check-milestone-copy.ts`.
  static const List<MilestoneKind> requiredKinds = MilestoneKind.values;
}

/// Concrete celebratory copy bundle.
final class MilestoneCopy {
  final String title;
  final String subtitle;
  final String shareText;

  const MilestoneCopy({
    required this.title,
    required this.subtitle,
    required this.shareText,
  });
}
