# OS-03 — Portal: Mural de Avisos

---

## Pages

### /announcements

- **Título:** Mural de Avisos
- **Conteúdo:**
  - Cards de resumo: total de avisos, taxa média de leitura (%), avisos nesta semana
  - Tabela: Título | Autor | Data | Fixado | Taxa de Leitura (%) | Ações
  - Botão "Novo Aviso" → formulário (inline ou modal)
  - Ações por linha: Ver, Editar, Fixar/Desfixar, Excluir
- **Cálculo da taxa de leitura:** `read_count / total_members * 100`

### /announcements/[id]

- **Conteúdo:**
  - Aviso completo (título, autor, data, corpo)
  - Estatísticas: "Lido por X de Y (Z%)"
  - Lista de quem leu + quando (para staff)
- **Query:** `coaching_announcement_reads` + join com `profiles` para nomes

---

## API

### GET /api/export/announcements

- **Query params:** `announcement_id` (opcional), `from`, `to`
- **Colunas CSV:** Título, Membro, Lido Em
- **Retorno:** `text/csv`
- **Permissão:** admin_master, coach, assistant

---

## Sidebar

- **Item:** "Mural"
- **Path:** `/announcements`
- **Roles:** admin_master, coach, assistant
- **Posição:** Após "CRM Atletas"

---

## Read Rate

```
read_rate = (read_count / total_members) * 100
```

- `read_count`: contagem em `coaching_announcement_reads` para o aviso
- `total_members`: contagem em `coaching_members` para o group_id do aviso
