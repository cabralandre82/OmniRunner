# OS-01 — Portal: Treinos Prescritos

> **Atualizado:** 2026-03-04 — DECISAO 134/135

## Sidebar

| Label | Href | Roles |
|-------|------|-------|
| Treinos Prescritos | `/attendance` | admin_master, coach, assistant |
| Análise de Treinos | `/attendance-analytics` | admin_master, coach, assistant |

## Páginas

### 1. Cumprimento dos Treinos (`/attendance`)

**Título:** "Cumprimento dos Treinos"  
**Subtítulo:** "Avaliação automática dos treinos prescritos nos últimos 30 dias"

**KPIs:**
| Card | Valor |
|------|-------|
| Treinos (período) | total de sessões |
| Taxa de conclusão | % de completed+present / total |
| Concluídos | contagem de status completed+present |
| Atletas no grupo | contagem de membros com role athlete/atleta |

**Tabela:**
| Coluna | Descrição |
|--------|-----------|
| Treino | Título (link para detalhe) |
| Data | `starts_at` formatado |
| **Distância** | `distance_target_m / 1000` km ou "—" |
| Concluídos | Contagem de completed+present |
| Total | Número de atletas |
| % | Taxa de conclusão |

**Filtros:** Data (de/até), sessão específica  
**Export:** CSV via `/api/export/attendance`

### 2. Detalhe do Treino (`/attendance/[id]`)

**Título:** Nome do treino  
**Subtítulo:** "Resultado dos atletas neste treino"

**Info do treino:**
- Data, Local, Status (Agendado/Realizado/Cancelado)
- **Distância alvo** (se definida)
- **Faixa de pace** (se definida)

**Resultado:**
- `N / total atletas = X%`
- Breakdown: N concluídos | N parciais | N ausentes

**Tabela:**
| Coluna | Descrição |
|--------|-----------|
| Nome | Display name do atleta |
| Avaliado em | Timestamp da avaliação |
| Método | QR / Manual / **Automático** |
| Status | Badge colorido: Concluído (verde), Parcial (amarelo), Ausente (vermelho), Presente, Atrasado, Justificado |

**Status colors:**
- `completed`, `present` → `bg-success-soft text-success`
- `partial`, `late` → `bg-warning-soft text-warning`
- `absent` → `bg-error-soft text-error`
- `excused` → `bg-info-soft text-info`

### 3. Análise de Treinos (`/attendance-analytics`)

**Título:** "Análise de Treinos Prescritos"  
**Subtítulo:** "Métricas e tendências de cumprimento dos treinos"

**KPIs:**
| Card | Valor |
|------|-------|
| Taxa média de conclusão | % média |
| Total de treinos no período | contagem |
| Total concluídos | contagem completed+present |
| Treinos com conclusão < 50% | contagem |

**Seções:**
1. **Treinos com Baixo Cumprimento** — tabela de sessões com taxa < 50%
2. **Cumprimento por Atleta** — tabela com nome, concluídos, taxa (%)

**Filtros:** Período (7/14/30 dias, custom range)

## API

### GET `/api/export/attendance`

Exporta CSV com todos os registros de cumprimento.

**Query params:** `from`, `to`, `session_id` (opcionais)

**Colunas CSV:**
```
Título Sessão,Data,Atleta,Check-in,Método,Status
```

**Valores de método:** QR, Manual, Automático  
**Valores de status:** Presente, Concluído, Parcial, Ausente, Atrasado, Justificado

## Exportações (`/exports`)

| Card | Título | Descrição |
|------|--------|-----------|
| attendance | Treinos Prescritos | Treinos, datas, atletas, status de cumprimento, método |

## CRM

| Página | Mudança |
|--------|---------|
| `/crm` | Coluna "Treinos" (era "Presenças"), subtítulo atualizado |
| `/crm/[userId]` | "Treinos Prescritos (últimos 30 dias)", "N treinos concluídos" |
