# OS-04 — Portal Profissional: Relatórios e Auditoria

## Migration

- **Arquivo:** `supabase/migrations/20260303700000_portal_performance_indexes.sql`

## Inventário de Páginas

| Página           | Path                 | Tabelas Fonte                                                                 | Propósito                                                        |
|------------------|----------------------|-------------------------------------------------------------------------------|------------------------------------------------------------------|
| Engajamento      | /engagement          | sessions, coaching_kpis_daily                                                 | DAU/WAU/MAU, tendência de score, lista de inativos               |
| Análise Presença | /attendance-analytics| coaching_training_sessions, coaching_training_attendance                      | Taxas de presença, sessões com baixa participação                |
| Alertas/Risco    | /risk                | coaching_alerts, profiles, coaching_member_status                            | Atletas em risco, resolver/rejeitar alertas                      |
| CRM              | /crm                 | coaching_members, coaching_tags, coaching_athlete_notes, coaching_member_status | Segmentação, notas, exportação                               |
| Comunicação      | /communications      | coaching_announcements, coaching_announcement_reads                           | Taxas de leitura, visão geral dos avisos                         |
| Exports          | /exports             | todos os módulos                                                              | Hub central de exportação CSV                                    |

## Regras de Performance

- Todas as queries devem ser **paginadas**
- `group_id` deve estar **indexado** em todas as consultas
- Evitar **full-table scans**; usar filtros e índices adequados
- Preferir **queries set-based** em vez de loops no aplicativo

## Acesso por Função

| Função      | Acesso                          |
|-------------|----------------------------------|
| admin_master| Acesso total a todas as páginas  |
| coach       | Maioria das páginas (exceto custódia, swap, fx) |
| assistant   | Apenas analytics em modo leitura (engajamento, presença, CRM, Mural) |
| athlete     | Sem acesso ao portal profissional |
