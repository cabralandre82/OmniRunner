import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/presentation/screens/athlete_championship_ranking_screen.dart';

import '../../helpers/test_di.dart';

void main() {
  group('AthleteChampionshipRankingScreen', () {
    setUp(() {
      ensureSupabaseClientRegistered();
    });

    test('widget accepts required parameters', () {
      const screen = AthleteChampionshipRankingScreen(
        championshipId: 'c1',
        championshipName: 'Campeonato Teste',
        metric: 'distance',
      );

      expect(screen.championshipId, 'c1');
      expect(screen.championshipName, 'Campeonato Teste');
      expect(screen.metric, 'distance');
    });

    test('accepts different metric types', () {
      const distScreen = AthleteChampionshipRankingScreen(
        championshipId: 'c1',
        championshipName: 'Distância Total',
        metric: 'distance',
      );
      const timeScreen = AthleteChampionshipRankingScreen(
        championshipId: 'c2',
        championshipName: 'Tempo Total',
        metric: 'time',
      );
      const paceScreen = AthleteChampionshipRankingScreen(
        championshipId: 'c3',
        championshipName: 'Melhor Pace',
        metric: 'pace',
      );

      expect(distScreen.metric, 'distance');
      expect(timeScreen.metric, 'time');
      expect(paceScreen.metric, 'pace');
    });

    // NOTE: Widget render tests require Supabase.initialize() because the
    // build() method accesses Supabase.instance.client directly.
    // Full widget tests can be added once a Supabase test helper is available.
  });
}
