import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/features/parks/domain/park_entity.dart';
import 'package:omni_runner/features/parks/data/park_detection_service.dart';

void main() {
  // Simple square polygon around (0,0): corners at (-1,-1), (-1,1), (1,1), (1,-1)
  const squarePark = ParkEntity(
    id: 'p1',
    name: 'Parque Teste',
    city: 'São Paulo',
    state: 'SP',
    polygon: [
      LatLng(-1, -1),
      LatLng(-1, 1),
      LatLng(1, 1),
      LatLng(1, -1),
    ],
    center: LatLng(0, 0),
  );

  const farPark = ParkEntity(
    id: 'p2',
    name: 'Parque Longe',
    city: 'Rio',
    state: 'RJ',
    polygon: [
      LatLng(10, 10),
      LatLng(10, 11),
      LatLng(11, 11),
      LatLng(11, 10),
    ],
    center: LatLng(10.5, 10.5),
  );

  late ParkDetectionService sut;

  setUp(() {
    sut = const ParkDetectionService([squarePark, farPark]);
  });

  group('detectPark', () {
    test('returns park when point is inside polygon', () {
      final result = sut.detectPark(0.0, 0.0);
      expect(result, isNotNull);
      expect(result!.id, 'p1');
    });

    test('returns null when point is outside all polygons', () {
      final result = sut.detectPark(5.0, 5.0);
      expect(result, isNull);
    });

    test('detects correct park among multiple', () {
      final result = sut.detectPark(10.5, 10.5);
      expect(result, isNotNull);
      expect(result!.id, 'p2');
    });

    test('returns null for a point just outside the polygon', () {
      final result = sut.detectPark(-1.5, 0.0);
      expect(result, isNull);
    });
  });

  group('findNearby', () {
    test('returns parks within given radius', () {
      // Center of squarePark is (0,0); querying from very close
      final results = sut.findNearby(0.001, 0.001, radiusM: 500);
      expect(results, hasLength(1));
      expect(results.first.id, 'p1');
    });

    test('returns empty when no parks within radius', () {
      final results = sut.findNearby(50.0, 50.0, radiusM: 100);
      expect(results, isEmpty);
    });

    test('results are sorted by distance', () {
      const svc = ParkDetectionService([farPark, squarePark]);
      final results = svc.findNearby(0.001, 0.001, radiusM: 2000000);
      expect(results.first.id, 'p1');
    });
  });

  group('ParkLeaderboardEntry.tierFromRank', () {
    test('rank 1 is rei', () {
      expect(ParkLeaderboardEntry.tierFromRank(1), ParkLeaderboardTier.rei);
    });

    test('rank 2-3 is elite', () {
      expect(ParkLeaderboardEntry.tierFromRank(2), ParkLeaderboardTier.elite);
      expect(ParkLeaderboardEntry.tierFromRank(3), ParkLeaderboardTier.elite);
    });

    test('rank 4-10 is destaque', () {
      expect(
          ParkLeaderboardEntry.tierFromRank(4), ParkLeaderboardTier.destaque);
      expect(
          ParkLeaderboardEntry.tierFromRank(10), ParkLeaderboardTier.destaque);
    });

    test('rank 11-20 is pelotao', () {
      expect(
          ParkLeaderboardEntry.tierFromRank(11), ParkLeaderboardTier.pelotao);
      expect(
          ParkLeaderboardEntry.tierFromRank(20), ParkLeaderboardTier.pelotao);
    });

    test('rank >20 is frequentador', () {
      expect(ParkLeaderboardEntry.tierFromRank(21),
          ParkLeaderboardTier.frequentador);
      expect(ParkLeaderboardEntry.tierFromRank(100),
          ParkLeaderboardTier.frequentador);
    });
  });
}
