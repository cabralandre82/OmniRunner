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

  ParkEntity(
    id: 'park_moinhos',
    name: 'Parque Moinhos de Vento (Parcão)',
    city: 'Porto Alegre',
    state: 'RS',
    center: LatLng(-30.0260, -51.2000),
    areaSqM: 115000,
    polygon: [
      LatLng(-30.0240, -51.2030),
      LatLng(-30.0240, -51.1970),
      LatLng(-30.0280, -51.1970),
      LatLng(-30.0280, -51.2030),
    ],
  ),

  // ── São Paulo (mais) ────────────────────────────────────────

  ParkEntity(
    id: 'park_carmo',
    name: 'Parque do Carmo',
    city: 'São Paulo',
    state: 'SP',
    center: LatLng(-23.5800, -46.4780),
    areaSqM: 1500000,
    polygon: [
      LatLng(-23.5740, -46.4840),
      LatLng(-23.5740, -46.4720),
      LatLng(-23.5860, -46.4720),
      LatLng(-23.5860, -46.4840),
    ],
  ),

  ParkEntity(
    id: 'park_aclimacao',
    name: 'Parque da Aclimação',
    city: 'São Paulo',
    state: 'SP',
    center: LatLng(-23.5715, -46.6335),
    areaSqM: 112000,
    polygon: [
      LatLng(-23.5695, -46.6360),
      LatLng(-23.5695, -46.6310),
      LatLng(-23.5735, -46.6310),
      LatLng(-23.5735, -46.6360),
    ],
  ),

  ParkEntity(
    id: 'park_piqueri',
    name: 'Parque Piqueri',
    city: 'São Paulo',
    state: 'SP',
    center: LatLng(-23.5280, -46.5750),
    areaSqM: 97000,
    polygon: [
      LatLng(-23.5260, -46.5780),
      LatLng(-23.5260, -46.5720),
      LatLng(-23.5300, -46.5720),
      LatLng(-23.5300, -46.5780),
    ],
  ),

  ParkEntity(
    id: 'park_ecologico_tiete',
    name: 'Parque Ecológico do Tietê',
    city: 'São Paulo',
    state: 'SP',
    center: LatLng(-23.5050, -46.5400),
    areaSqM: 14000000,
    polygon: [
      LatLng(-23.4970, -46.5500),
      LatLng(-23.4970, -46.5300),
      LatLng(-23.5130, -46.5300),
      LatLng(-23.5130, -46.5500),
    ],
  ),

  ParkEntity(
    id: 'park_independencia',
    name: 'Parque da Independência',
    city: 'São Paulo',
    state: 'SP',
    center: LatLng(-23.5850, -46.6115),
    areaSqM: 161000,
    polygon: [
      LatLng(-23.5830, -46.6140),
      LatLng(-23.5830, -46.6090),
      LatLng(-23.5870, -46.6090),
      LatLng(-23.5870, -46.6140),
    ],
  ),

  // ── Rio de Janeiro (mais) ────────────────────────────────────

  ParkEntity(
    id: 'park_quinta_boa_vista',
    name: 'Quinta da Boa Vista',
    city: 'Rio de Janeiro',
    state: 'RJ',
    center: LatLng(-22.9060, -43.2230),
    areaSqM: 155000,
    polygon: [
      LatLng(-22.9030, -43.2270),
      LatLng(-22.9030, -43.2190),
      LatLng(-22.9090, -43.2190),
      LatLng(-22.9090, -43.2270),
    ],
  ),

  ParkEntity(
    id: 'park_tijuca',
    name: 'Parque Nacional da Tijuca',
    city: 'Rio de Janeiro',
    state: 'RJ',
    center: LatLng(-22.9570, -43.2870),
    areaSqM: 39530000,
    polygon: [
      LatLng(-22.9300, -43.3100),
      LatLng(-22.9300, -43.2640),
      LatLng(-22.9840, -43.2640),
      LatLng(-22.9840, -43.3100),
    ],
  ),

  ParkEntity(
    id: 'park_orla_copacabana',
    name: 'Orla de Copacabana',
    city: 'Rio de Janeiro',
    state: 'RJ',
    center: LatLng(-22.9711, -43.1823),
    areaSqM: 160000,
    polygon: [
      LatLng(-22.9660, -43.1880),
      LatLng(-22.9660, -43.1770),
      LatLng(-22.9770, -43.1770),
      LatLng(-22.9770, -43.1880),
    ],
  ),

  // ── Brasília (mais) ──────────────────────────────────────────

  ParkEntity(
    id: 'park_agua_mineral',
    name: 'Parque Nacional de Brasília (Água Mineral)',
    city: 'Brasília',
    state: 'DF',
    center: LatLng(-15.7350, -47.9300),
    areaSqM: 42389000,
    polygon: [
      LatLng(-15.6800, -47.9800),
      LatLng(-15.6800, -47.8800),
      LatLng(-15.7900, -47.8800),
      LatLng(-15.7900, -47.9800),
    ],
  ),

  ParkEntity(
    id: 'park_olhos_dagua',
    name: 'Parque Olhos D\'Água',
    city: 'Brasília',
    state: 'DF',
    center: LatLng(-15.7700, -47.8600),
    areaSqM: 210000,
    polygon: [
      LatLng(-15.7680, -47.8630),
      LatLng(-15.7680, -47.8570),
      LatLng(-15.7720, -47.8570),
      LatLng(-15.7720, -47.8630),
    ],
  ),

  ParkEntity(
    id: 'park_ermida_dom_bosco',
    name: 'Ermida Dom Bosco / Orla do Lago',
    city: 'Brasília',
    state: 'DF',
    center: LatLng(-15.8350, -47.8400),
    areaSqM: 50000,
    polygon: [
      LatLng(-15.8330, -47.8430),
      LatLng(-15.8330, -47.8370),
      LatLng(-15.8370, -47.8370),
      LatLng(-15.8370, -47.8430),
    ],
  ),

  // ── Recife ──────────────────────────────────────────────────

  ParkEntity(
    id: 'park_jaqueira',
    name: 'Parque da Jaqueira',
    city: 'Recife',
    state: 'PE',
    center: LatLng(-8.0370, -34.8990),
    areaSqM: 70000,
    polygon: [
      LatLng(-8.0350, -34.9010),
      LatLng(-8.0350, -34.8970),
      LatLng(-8.0390, -34.8970),
      LatLng(-8.0390, -34.9010),
    ],
  ),

  ParkEntity(
    id: 'park_dona_lindu',
    name: 'Parque Dona Lindu',
    city: 'Recife',
    state: 'PE',
    center: LatLng(-8.1300, -34.9060),
    areaSqM: 27000,
    polygon: [
      LatLng(-8.1285, -34.9080),
      LatLng(-8.1285, -34.9040),
      LatLng(-8.1315, -34.9040),
      LatLng(-8.1315, -34.9080),
    ],
  ),

  // ── Salvador ────────────────────────────────────────────────

  ParkEntity(
    id: 'park_pituacu',
    name: 'Parque Metropolitano de Pituaçu',
    city: 'Salvador',
    state: 'BA',
    center: LatLng(-12.9600, -38.4300),
    areaSqM: 4250000,
    polygon: [
      LatLng(-12.9500, -38.4400),
      LatLng(-12.9500, -38.4200),
      LatLng(-12.9700, -38.4200),
      LatLng(-12.9700, -38.4400),
    ],
  ),

  ParkEntity(
    id: 'park_cidade_salvador',
    name: 'Parque da Cidade (Salvador)',
    city: 'Salvador',
    state: 'BA',
    center: LatLng(-13.0050, -38.4630),
    areaSqM: 720000,
    polygon: [
      LatLng(-13.0010, -38.4670),
      LatLng(-13.0010, -38.4590),
      LatLng(-13.0090, -38.4590),
      LatLng(-13.0090, -38.4670),
    ],
  ),

  // ── Fortaleza ───────────────────────────────────────────────

  ParkEntity(
    id: 'park_cocó',
    name: 'Parque do Cocó',
    city: 'Fortaleza',
    state: 'CE',
    center: LatLng(-3.7450, -38.4900),
    areaSqM: 1571000,
    polygon: [
      LatLng(-3.7370, -38.4970),
      LatLng(-3.7370, -38.4830),
      LatLng(-3.7530, -38.4830),
      LatLng(-3.7530, -38.4970),
    ],
  ),

  ParkEntity(
    id: 'park_beira_mar_fortaleza',
    name: 'Calçadão da Beira-Mar',
    city: 'Fortaleza',
    state: 'CE',
    center: LatLng(-3.7250, -38.5050),
    areaSqM: 80000,
    polygon: [
      LatLng(-3.7230, -38.5120),
      LatLng(-3.7230, -38.4980),
      LatLng(-3.7270, -38.4980),
      LatLng(-3.7270, -38.5120),
    ],
  ),

  // ── Curitiba (mais) ──────────────────────────────────────────

  ParkEntity(
    id: 'park_tangua',
    name: 'Parque Tanguá',
    city: 'Curitiba',
    state: 'PR',
    center: LatLng(-25.3835, -49.2846),
    areaSqM: 235000,
    polygon: [
      LatLng(-25.3810, -49.2880),
      LatLng(-25.3810, -49.2810),
      LatLng(-25.3860, -49.2810),
      LatLng(-25.3860, -49.2880),
    ],
  ),

  ParkEntity(
    id: 'park_botanico_curitiba',
    name: 'Jardim Botânico de Curitiba',
    city: 'Curitiba',
    state: 'PR',
    center: LatLng(-25.4420, -49.2373),
    areaSqM: 178000,
    polygon: [
      LatLng(-25.4395, -49.2410),
      LatLng(-25.4395, -49.2335),
      LatLng(-25.4445, -49.2335),
      LatLng(-25.4445, -49.2410),
    ],
  ),

  // ── Belo Horizonte (mais) ────────────────────────────────────

  ParkEntity(
    id: 'park_lagoa_pampulha',
    name: 'Orla da Lagoa da Pampulha',
    city: 'Belo Horizonte',
    state: 'MG',
    center: LatLng(-19.8630, -43.9700),
    areaSqM: 3800000,
    polygon: [
      LatLng(-19.8500, -43.9830),
      LatLng(-19.8500, -43.9570),
      LatLng(-19.8760, -43.9570),
      LatLng(-19.8760, -43.9830),
    ],
  ),

  ParkEntity(
    id: 'park_municipal_bh',
    name: 'Parque Municipal Américo Renné Giannetti',
    city: 'Belo Horizonte',
    state: 'MG',
    center: LatLng(-19.9290, -43.9370),
    areaSqM: 182000,
    polygon: [
      LatLng(-19.9270, -43.9400),
      LatLng(-19.9270, -43.9340),
      LatLng(-19.9310, -43.9340),
      LatLng(-19.9310, -43.9400),
    ],
  ),

  // ── Goiânia ──────────────────────────────────────────────────

  ParkEntity(
    id: 'park_flamboyant',
    name: 'Parque Flamboyant',
    city: 'Goiânia',
    state: 'GO',
    center: LatLng(-16.7130, -49.2430),
    areaSqM: 125000,
    polygon: [
      LatLng(-16.7110, -49.2460),
      LatLng(-16.7110, -49.2400),
      LatLng(-16.7150, -49.2400),
      LatLng(-16.7150, -49.2460),
    ],
  ),

  ParkEntity(
    id: 'park_vacas_brava',
    name: 'Parque Vaca Brava',
    city: 'Goiânia',
    state: 'GO',
    center: LatLng(-16.7050, -49.2720),
    areaSqM: 19000,
    polygon: [
      LatLng(-16.7035, -49.2740),
      LatLng(-16.7035, -49.2700),
      LatLng(-16.7065, -49.2700),
      LatLng(-16.7065, -49.2740),
    ],
  ),

  ParkEntity(
    id: 'park_bosque_buritis',
    name: 'Bosque dos Buritis',
    city: 'Goiânia',
    state: 'GO',
    center: LatLng(-16.6810, -49.2690),
    areaSqM: 120000,
    polygon: [
      LatLng(-16.6790, -49.2720),
      LatLng(-16.6790, -49.2660),
      LatLng(-16.6830, -49.2660),
      LatLng(-16.6830, -49.2720),
    ],
  ),

  // ── Manaus ──────────────────────────────────────────────────

  ParkEntity(
    id: 'park_mindu',
    name: 'Parque Municipal do Mindú',
    city: 'Manaus',
    state: 'AM',
    center: LatLng(-3.0960, -60.0200),
    areaSqM: 330000,
    polygon: [
      LatLng(-3.0940, -60.0230),
      LatLng(-3.0940, -60.0170),
      LatLng(-3.0980, -60.0170),
      LatLng(-3.0980, -60.0230),
    ],
  ),

  // ── Belém ──────────────────────────────────────────────────

  ParkEntity(
    id: 'park_bosque_rodrigues_alves',
    name: 'Bosque Rodrigues Alves',
    city: 'Belém',
    state: 'PA',
    center: LatLng(-1.4280, -48.4700),
    areaSqM: 150000,
    polygon: [
      LatLng(-1.4260, -48.4720),
      LatLng(-1.4260, -48.4680),
      LatLng(-1.4300, -48.4680),
      LatLng(-1.4300, -48.4720),
    ],
  ),

  // ── Florianópolis ──────────────────────────────────────────

  ParkEntity(
    id: 'park_beira_mar_floripa',
    name: 'Parque Linear Beira-Mar',
    city: 'Florianópolis',
    state: 'SC',
    center: LatLng(-27.5870, -48.5400),
    areaSqM: 70000,
    polygon: [
      LatLng(-27.5830, -48.5440),
      LatLng(-27.5830, -48.5360),
      LatLng(-27.5910, -48.5360),
      LatLng(-27.5910, -48.5440),
    ],
  ),

  // ── Campinas ─────────────────────────────────────────────────

  ParkEntity(
    id: 'park_taquaral',
    name: 'Parque Portugal (Taquaral)',
    city: 'Campinas',
    state: 'SP',
    center: LatLng(-22.8710, -47.0490),
    areaSqM: 650000,
    polygon: [
      LatLng(-22.8670, -47.0540),
      LatLng(-22.8670, -47.0440),
      LatLng(-22.8750, -47.0440),
      LatLng(-22.8750, -47.0540),
    ],
  ),

  // ── Vitória ─────────────────────────────────────────────────

  ParkEntity(
    id: 'park_pedra_cebola',
    name: 'Parque Pedra da Cebola',
    city: 'Vitória',
    state: 'ES',
    center: LatLng(-20.2860, -40.2890),
    areaSqM: 100000,
    polygon: [
      LatLng(-20.2840, -40.2910),
      LatLng(-20.2840, -40.2870),
      LatLng(-20.2880, -40.2870),
      LatLng(-20.2880, -40.2910),
    ],
  ),

  // ── Natal ──────────────────────────────────────────────────

  ParkEntity(
    id: 'park_cidade_natal',
    name: 'Parque da Cidade (Natal)',
    city: 'Natal',
    state: 'RN',
    center: LatLng(-5.8450, -35.2130),
    areaSqM: 640000,
    polygon: [
      LatLng(-5.8400, -35.2180),
      LatLng(-5.8400, -35.2080),
      LatLng(-5.8500, -35.2080),
      LatLng(-5.8500, -35.2180),
    ],
  ),

  // ── São Luís ──────────────────────────────────────────────

  ParkEntity(
    id: 'park_lagoa_jansen',
    name: 'Parque Ecológico da Lagoa da Jansen',
    city: 'São Luís',
    state: 'MA',
    center: LatLng(-2.4980, -44.2870),
    areaSqM: 150000,
    polygon: [
      LatLng(-2.4960, -44.2900),
      LatLng(-2.4960, -44.2840),
      LatLng(-2.5000, -44.2840),
      LatLng(-2.5000, -44.2900),
    ],
  ),

  // ── Campo Grande ──────────────────────────────────────────

  ParkEntity(
    id: 'park_nacoes_indigenas',
    name: 'Parque das Nações Indígenas',
    city: 'Campo Grande',
    state: 'MS',
    center: LatLng(-20.4530, -54.5880),
    areaSqM: 1190000,
    polygon: [
      LatLng(-20.4470, -54.5940),
      LatLng(-20.4470, -54.5820),
      LatLng(-20.4590, -54.5820),
      LatLng(-20.4590, -54.5940),
    ],
  ),

  // ── João Pessoa ──────────────────────────────────────────────

  ParkEntity(
    id: 'park_solon_lucena',
    name: 'Parque Solon de Lucena (Lagoa)',
    city: 'João Pessoa',
    state: 'PB',
    center: LatLng(-7.1190, -34.8780),
    areaSqM: 65000,
    polygon: [
      LatLng(-7.1170, -34.8800),
      LatLng(-7.1170, -34.8760),
      LatLng(-7.1210, -34.8760),
      LatLng(-7.1210, -34.8800),
    ],
  ),

  // ── Niterói ──────────────────────────────────────────────────

  ParkEntity(
    id: 'park_cidade_niteroi',
    name: 'Parque da Cidade (Niterói)',
    city: 'Niterói',
    state: 'RJ',
    center: LatLng(-22.9330, -43.0840),
    areaSqM: 149000,
    polygon: [
      LatLng(-22.9310, -43.0870),
      LatLng(-22.9310, -43.0810),
      LatLng(-22.9350, -43.0810),
      LatLng(-22.9350, -43.0870),
    ],
  ),

  // ── Santos ──────────────────────────────────────────────────

  ParkEntity(
    id: 'park_orla_santos',
    name: 'Orla de Santos',
    city: 'Santos',
    state: 'SP',
    center: LatLng(-23.9700, -46.3350),
    areaSqM: 200000,
    polygon: [
      LatLng(-23.9660, -46.3500),
      LatLng(-23.9660, -46.3200),
      LatLng(-23.9740, -46.3200),
      LatLng(-23.9740, -46.3500),
    ],
  ),

  // ── Ribeirão Preto ──────────────────────────────────────────

  ParkEntity(
    id: 'park_curupira',
    name: 'Parque Curupira',
    city: 'Ribeirão Preto',
    state: 'SP',
    center: LatLng(-21.1850, -47.8280),
    areaSqM: 120000,
    polygon: [
      LatLng(-21.1830, -47.8310),
      LatLng(-21.1830, -47.8250),
      LatLng(-21.1870, -47.8250),
      LatLng(-21.1870, -47.8310),
    ],
  ),
];
