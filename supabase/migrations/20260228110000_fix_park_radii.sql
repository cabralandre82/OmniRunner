-- ============================================================================
-- Fix park radii for large parks where 
-- start points near edges fall outside radius
-- Date: 2026-02-28
-- ============================================================================

BEGIN;

-- Parque da Cidade Sarah Kubitschek (Brasília) is ~4.5km long
-- 1200m radius misses start points near park edges
UPDATE public.parks SET radius_m = 1800
WHERE id = 'park_cidade_brasilia';

-- Parque Nacional da Tijuca (Rio) is massive, 3000m may be tight
UPDATE public.parks SET radius_m = 4000
WHERE id = 'park_tijuca';

-- Parque Ecológico do Tietê (SP) is 14km², current 1500m insufficient
UPDATE public.parks SET radius_m = 2500
WHERE id = 'park_ecologico_tiete';

-- Parque Nacional de Brasília (Água Mineral) is 42km²
UPDATE public.parks SET radius_m = 5000
WHERE id = 'park_agua_mineral';

COMMIT;
