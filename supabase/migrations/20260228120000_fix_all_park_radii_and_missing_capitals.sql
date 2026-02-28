-- ============================================================================
-- Fix ALL park radii + add missing state capital parks
-- Date: 2026-02-28
-- Origin: DECISÃO 123
-- Method: haversine(center, farthest polygon vertex) + 200m buffer
-- ============================================================================

BEGIN;

-- ═══════════════════════════════════════════════════════════════════════════
-- 1. Fix radii for ALL existing parks
-- ═══════════════════════════════════════════════════════════════════════════

UPDATE public.parks SET radius_m = 900   WHERE id = 'park_ibirapuera';
UPDATE public.parks SET radius_m = 850   WHERE id = 'park_villa_lobos';
UPDATE public.parks SET radius_m = 600   WHERE id = 'park_povo';
UPDATE public.parks SET radius_m = 750   WHERE id = 'park_ceret';
UPDATE public.parks SET radius_m = 1700  WHERE id = 'park_aterro_flamengo';
UPDATE public.parks SET radius_m = 1700  WHERE id = 'park_lagoa';
UPDATE public.parks SET radius_m = 1550  WHERE id = 'park_barigui';
-- park_cidade_brasilia already 1800 (OK)
UPDATE public.parks SET radius_m = 1600  WHERE id = 'park_mangabeiras';
UPDATE public.parks SET radius_m = 850   WHERE id = 'park_redempcao';
UPDATE public.parks SET radius_m = 600   WHERE id = 'park_moinhos';
UPDATE public.parks SET radius_m = 1150  WHERE id = 'park_carmo';
UPDATE public.parks SET radius_m = 550   WHERE id = 'park_aclimacao';
UPDATE public.parks SET radius_m = 600   WHERE id = 'park_piqueri';
-- park_ecologico_tiete already 2500 (OK, generous)
UPDATE public.parks SET radius_m = 550   WHERE id = 'park_independencia';
UPDATE public.parks SET radius_m = 750   WHERE id = 'park_quinta_boa_vista';
UPDATE public.parks SET radius_m = 4100  WHERE id = 'park_tijuca';
UPDATE public.parks SET radius_m = 1100  WHERE id = 'park_orla_copacabana';
-- park_agua_mineral already 5000 (running area; full park is 8km+)
UPDATE public.parks SET radius_m = 600   WHERE id = 'park_olhos_dagua';
UPDATE public.parks SET radius_m = 600   WHERE id = 'park_ermida_dom_bosco';
UPDATE public.parks SET radius_m = 550   WHERE id = 'park_jaqueira';
UPDATE public.parks SET radius_m = 500   WHERE id = 'park_dona_lindu';
UPDATE public.parks SET radius_m = 1800  WHERE id = 'park_pituacu';
UPDATE public.parks SET radius_m = 850   WHERE id = 'park_cidade_salvador';
UPDATE public.parks SET radius_m = 1400  WHERE id = 'park_cocó';
UPDATE public.parks SET radius_m = 1050  WHERE id = 'park_beira_mar_fortaleza';
UPDATE public.parks SET radius_m = 700   WHERE id = 'park_tangua';
UPDATE public.parks SET radius_m = 700   WHERE id = 'park_botanico_curitiba';
UPDATE public.parks SET radius_m = 2200  WHERE id = 'park_lagoa_pampulha';
UPDATE public.parks SET radius_m = 600   WHERE id = 'park_municipal_bh';
UPDATE public.parks SET radius_m = 600   WHERE id = 'park_flamboyant';
UPDATE public.parks SET radius_m = 500   WHERE id = 'park_vacas_brava';
UPDATE public.parks SET radius_m = 600   WHERE id = 'park_bosque_buritis';
UPDATE public.parks SET radius_m = 650   WHERE id = 'park_mindu';
UPDATE public.parks SET radius_m = 550   WHERE id = 'park_bosque_rodrigues_alves';
UPDATE public.parks SET radius_m = 800   WHERE id = 'park_beira_mar_floripa';
UPDATE public.parks SET radius_m = 900   WHERE id = 'park_taquaral';
UPDATE public.parks SET radius_m = 550   WHERE id = 'park_pedra_cebola';
UPDATE public.parks SET radius_m = 1000  WHERE id = 'park_cidade_natal';
UPDATE public.parks SET radius_m = 650   WHERE id = 'park_lagoa_jansen';
UPDATE public.parks SET radius_m = 1150  WHERE id = 'park_nacoes_indigenas';
UPDATE public.parks SET radius_m = 550   WHERE id = 'park_solon_lucena';
UPDATE public.parks SET radius_m = 600   WHERE id = 'park_cidade_niteroi';
UPDATE public.parks SET radius_m = 1800  WHERE id = 'park_orla_santos';
UPDATE public.parks SET radius_m = 600   WHERE id = 'park_curupira';

-- ═══════════════════════════════════════════════════════════════════════════
-- 2. Add parks for missing state capitals (9 capitals)
-- ═══════════════════════════════════════════════════════════════════════════

INSERT INTO public.parks (id, name, city, state, center_lat, center_lng, radius_m, area_sq_m) VALUES
  -- Aracaju (SE)
  ('park_sementeira', 'Parque Augusto Franco (Sementeira)', 'Aracaju', 'SE', -10.9250, -37.0660, 800, 400000),
  -- Maceió (AL)
  ('park_municipal_maceio', 'Parque Municipal de Maceió', 'Maceió', 'AL', -9.6480, -35.7250, 700, 200000),
  -- Macapá (AP)
  ('park_forte_macapa', 'Complexo do Forte de Macapá', 'Macapá', 'AP', 0.0340, -51.0520, 500, 40000),
  -- Cuiabá (MT)
  ('park_mae_bonifacia', 'Parque Mãe Bonifácia', 'Cuiabá', 'MT', -15.5780, -56.0870, 1000, 770000),
  -- Teresina (PI)
  ('park_potycabana', 'Parque Potycabana', 'Teresina', 'PI', -5.0630, -42.7790, 500, 50000),
  -- Porto Velho (RO)
  ('park_cidade_porto_velho', 'Parque da Cidade de Porto Velho', 'Porto Velho', 'RO', -8.7600, -63.9000, 600, 100000),
  -- Boa Vista (RR)
  ('park_anaua', 'Parque Anauá', 'Boa Vista', 'RR', 2.8190, -60.6800, 600, 120000),
  -- Rio Branco (AC)
  ('park_maternidade', 'Parque da Maternidade', 'Rio Branco', 'AC', -9.9730, -67.8100, 1500, 130000),
  -- Palmas (TO)
  ('park_cesamar', 'Parque Cesamar', 'Palmas', 'TO', -10.2050, -48.3250, 700, 200000)
ON CONFLICT (id) DO UPDATE SET
  radius_m = EXCLUDED.radius_m,
  area_sq_m = EXCLUDED.area_sq_m;

COMMIT;
