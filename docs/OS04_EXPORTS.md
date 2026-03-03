# OS-04 — Central de Exports CSV

## Endpoints de Exportação

| Módulo      | Endpoint                  | Colunas                                                                 |
|-------------|---------------------------|-------------------------------------------------------------------------|
| Engajamento | /api/export/engagement    | Dia, Score, Atletas, Coaches, Risco                                      |
| Presença    | /api/export/attendance    | Sessão, Data, Atleta, Check-in, Método, Status                          |
| CRM         | /api/export/crm           | Nome, Status, Tags, Presenças, Alertas, Última Nota                      |
| Avisos      | /api/export/announcements | Título, Membro, Lido Em                                                 |
| Alertas     | /api/export/alerts        | Atleta, Tipo, Dia, Resolvido, Data Resolução                            |

## Parâmetros Comuns

- `from` (date): data inicial do período
- `to` (date): data final do período
- Filtros opcionais específicos por módulo (status, tipo de alerta, etc.)

## Autenticação

Todos os endpoints exigem:

- Sessão autenticada
- Pertencimento ao grupo (via cookie `portal_group_id` ou header)
- Função compatível com o recurso (admin_master, coach, assistant conforme módulo)

## Formato

- **Encoding:** UTF-8 com BOM
- **Content-Disposition:** attachment (download forçado)
- **Content-Type:** text/csv; charset=utf-8
