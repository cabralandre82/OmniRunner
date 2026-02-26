import 'package:omni_runner/features/parks/domain/park_entity.dart';

/// Initial seed of popular Brazilian running parks.
///
/// Polygons are simplified approximations from OpenStreetMap.
/// In production, these would come from a Supabase table
/// and be cached locally. This seed provides offline detection
/// for the most popular parks while the full database loads.
const List<ParkEntity> kBrazilianParksSeed = [
  // ── São Paulo ──────────────────────────────────────────────

  ParkEntity(
    id: 'park_ibirapuera',
    name: 'Parque Ibirapuera',
    city: 'São Paulo',
    state: 'SP',
    center: LatLng(-23.5874, -46.6576),
    areaSqM: 1584000,
    polygon: [
      LatLng(-23.5830, -46.6620),
      LatLng(-23.5830, -46.6530),
      LatLng(-23.5920, -46.6530),
      LatLng(-23.5920, -46.6620),
    ],
  ),

  ParkEntity(
    id: 'park_villa_lobos',
    name: 'Parque Villa-Lobos',
    city: 'São Paulo',
    state: 'SP',
    center: LatLng(-23.5468, -46.7219),
    areaSqM: 732000,
    polygon: [
      LatLng(-23.5440, -46.7270),
      LatLng(-23.5440, -46.7170),
      LatLng(-23.5500, -46.7170),
      LatLng(-23.5500, -46.7270),
    ],
  ),

  ParkEntity(
    id: 'park_povo',
    name: 'Parque do Povo',
    city: 'São Paulo',
    state: 'SP',
    center: LatLng(-23.5856, -46.6908),
    areaSqM: 133000,
    polygon: [
      LatLng(-23.5838, -46.6935),
      LatLng(-23.5838, -46.6880),
      LatLng(-23.5878, -46.6880),
      LatLng(-23.5878, -46.6935),
    ],
  ),

  ParkEntity(
    id: 'park_ceret',
    name: 'CERET',
    city: 'São Paulo',
    state: 'SP',
    center: LatLng(-23.5757, -46.5896),
    areaSqM: 286000,
    polygon: [
      LatLng(-23.5730, -46.5930),
      LatLng(-23.5730, -46.5860),
      LatLng(-23.5790, -46.5860),
      LatLng(-23.5790, -46.5930),
    ],
  ),

  // ── Rio de Janeiro ─────────────────────────────────────────

  ParkEntity(
    id: 'park_aterro_flamengo',
    name: 'Aterro do Flamengo',
    city: 'Rio de Janeiro',
    state: 'RJ',
    center: LatLng(-22.9320, -43.1740),
    areaSqM: 1200000,
    polygon: [
      LatLng(-22.9210, -43.1800),
      LatLng(-22.9210, -43.1680),
      LatLng(-22.9440, -43.1680),
      LatLng(-22.9440, -43.1800),
    ],
  ),

  ParkEntity(
    id: 'park_lagoa',
    name: 'Lagoa Rodrigo de Freitas',
    city: 'Rio de Janeiro',
    state: 'RJ',
    center: LatLng(-22.9711, -43.2105),
    areaSqM: 2180000,
    polygon: [
      LatLng(-22.9630, -43.2210),
      LatLng(-22.9630, -43.2000),
      LatLng(-22.9800, -43.2000),
      LatLng(-22.9800, -43.2210),
    ],
  ),

  // ── Curitiba ───────────────────────────────────────────────

  ParkEntity(
    id: 'park_barigui',
    name: 'Parque Barigui',
    city: 'Curitiba',
    state: 'PR',
    center: LatLng(-25.4230, -49.3115),
    areaSqM: 1400000,
    polygon: [
      LatLng(-25.4120, -49.3170),
      LatLng(-25.4120, -49.3060),
      LatLng(-25.4340, -49.3060),
      LatLng(-25.4340, -49.3170),
    ],
  ),

  // ── Brasília ───────────────────────────────────────────────

  ParkEntity(
    id: 'park_cidade_brasilia',
    name: 'Parque da Cidade Sarah Kubitschek',
    city: 'Brasília',
    state: 'DF',
    center: LatLng(-15.8050, -47.8920),
    areaSqM: 4200000,
    polygon: [
      LatLng(-15.7960, -47.9010),
      LatLng(-15.7960, -47.8830),
      LatLng(-15.8150, -47.8830),
      LatLng(-15.8150, -47.9010),
    ],
  ),

  // ── Belo Horizonte ─────────────────────────────────────────

  ParkEntity(
    id: 'park_mangabeiras',
    name: 'Parque das Mangabeiras',
    city: 'Belo Horizonte',
    state: 'MG',
    center: LatLng(-19.9530, -43.9180),
    areaSqM: 2350000,
    polygon: [
      LatLng(-19.9440, -43.9270),
      LatLng(-19.9440, -43.9090),
      LatLng(-19.9620, -43.9090),
      LatLng(-19.9620, -43.9270),
    ],
  ),

  // ── Porto Alegre ───────────────────────────────────────────

  ParkEntity(
    id: 'park_redempcao',
    name: 'Parque da Redenção',
    city: 'Porto Alegre',
    state: 'RS',
    center: LatLng(-30.0385, -51.2140),
    areaSqM: 376000,
    polygon: [
      LatLng(-30.0350, -51.2190),
      LatLng(-30.0350, -51.2090),
      LatLng(-30.0420, -51.2090),
      LatLng(-30.0420, -51.2190),
    ],
  ),
];
