---
id: L04-04
audit_ref: "4.4"
lens: 4
title: "Dados de saúde/biométricos (dados sensíveis, LGPD Art. 11) sem proteção reforçada"
severity: critical
status: fix-pending
wave: 0
discovered_at: 2026-04-17
tags: ["lgpd", "rls", "gps", "mobile", "migration", "testing"]
files: []
correction_type: process
test_required: true
tests: []
linked_issues: []
linked_prs: []
owner: unassigned
runbook: null
effort_points: 5
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: null
---
# [L04-04] Dados de saúde/biométricos (dados sensíveis, LGPD Art. 11) sem proteção reforçada
> **Lente:** 4 — CLO · **Severidade:** 🔴 Critical · **Onda:** 0 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `sessions`, `running_dna_profiles`, `coaching_athlete_kpis_daily` armazenam:
- Frequência cardíaca média/max
- Pace/ritmo (indicador de condicionamento físico)
- Trajetórias GPS (localização precisa)
- Lesões/queixas em `support_tickets`

Estes são **dados pessoais sensíveis**. Auditoria não encontrou:
- Segregação (tabela separada + RLS reforçada)
- Criptografia em repouso adicional (coluna `pgp_sym_encrypt`)
- Log de acesso a dados sensíveis
- Minimização (apenas treinador do atleta pode ler)
## Risco / Impacto

— Vazamento de dados de saúde = enforcement agravado LGPD Art. 52 + possível ação coletiva (atletas públicos/profissionais).

## Correção proposta

—

```sql
-- Tabela separada para dados de saúde
CREATE TABLE public.athlete_health_data (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id),
  resting_hr_bpm integer,
  max_hr_bpm integer,
  vo2_max numeric(4,1),
  self_reported_injuries text, -- pgp_sym_encrypt applied at app layer
  updated_at timestamptz DEFAULT now()
);

ALTER TABLE public.athlete_health_data ENABLE ROW LEVEL SECURITY;

CREATE POLICY athlete_reads_own ON public.athlete_health_data
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY coach_reads_athlete ON public.athlete_health_data
  FOR SELECT USING (EXISTS (
    SELECT 1 FROM coaching_members cm1
    JOIN coaching_members cm2 ON cm1.group_id = cm2.group_id
    WHERE cm1.user_id = auth.uid()
      AND cm1.role IN ('coach','assistant','admin_master')
      AND cm2.user_id = athlete_health_data.user_id
      AND cm2.role = 'athlete'
  ));

-- Audit trigger
CREATE TRIGGER trg_audit_health_access AFTER SELECT ON athlete_health_data
  FOR EACH ROW EXECUTE FUNCTION fn_log_sensitive_access();
```

## Teste de regressão

— `athlete_health_data.rls.test`: coach de outro grupo não lê; atleta lê o próprio; platform_admin (se permitido por política) lê registrando audit_log.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[4.4]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 4 — CLO, item 4.4).