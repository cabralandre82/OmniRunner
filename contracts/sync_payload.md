# Sync Payload Specification

> **Sprint:** 9.2
> **Status:** Ativo
> **Referencia:** DECISAO 010 (Supabase backend), DECISAO 007 (Protobuf scope)

---

## 1. Visao Geral

O sync de uma sessao de corrida consiste em **dois uploads atomicos**:

1. **Points payload** — arquivo JSON com todos os pontos GPS da sessao,
   enviado ao Supabase Storage.
2. **Session metadata** — registro JSON leve com metadados da sessao,
   inserido na tabela Postgres `sessions` via Supabase REST.

O upload so e considerado completo quando ambos sao bem-sucedidos.
Se qualquer um falhar, a sessao permanece `isSynced = false` localmente.

### Desvio do plano original

O plano original mencionava "upload binario (Uint8List) do workout protobuf".
Conforme DECISAO 007 (Protobuf removido para modelos locais) e DECISAO 010
(JSON como wire format MVP), o formato adotado e **JSON puro**.
Protobuf permanece como opcao para otimizacao pos-MVP se o tamanho
dos payloads se tornar problema.

---

## 2. Points Payload (Storage)

### Destino

```
Supabase Storage
Bucket:  session-points
Path:    {user_id}/{session_uuid}.json
MIME:    application/json
```

### Formato

Array JSON de objetos `LocationPoint`. Cada objeto corresponde a um
`LocationPointEntity` do domain.

```json
[
  {
    "lat": -23.550520,
    "lng": -46.633308,
    "alt": 760.0,
    "accuracy": 5.2,
    "speed": 3.1,
    "bearing": 180.0,
    "timestampMs": 1707753600000
  },
  {
    "lat": -23.550480,
    "lng": -46.633250,
    "alt": 760.5,
    "accuracy": 4.8,
    "speed": 3.3,
    "bearing": 178.5,
    "timestampMs": 1707753601000
  }
]
```

### Schema de cada ponto

| Campo | Tipo | Obrigatorio | Unidade | Notas |
|---|---|---|---|---|
| lat | number | SIM | graus decimais | -90 a 90 (WGS84) |
| lng | number | SIM | graus decimais | -180 a 180 (WGS84) |
| alt | number | NAO | metros | Altitude acima do nivel do mar |
| accuracy | number | NAO | metros | Precisao horizontal GPS |
| speed | number | NAO | m/s | Velocidade instantanea |
| bearing | number | NAO | graus | 0-360, direcao |
| timestampMs | integer | SIM | milissegundos | Unix epoch UTC |

### Campos opcionais

Campos `null` no Dart sao **omitidos** do JSON (nao enviados como `null`).
Isso reduz tamanho do payload em ~20% para pontos com altitude/bearing ausentes.

### Estimativas de tamanho

| Duracao | Pontos (~1/s) | JSON bruto | JSON minificado |
|---|---|---|---|
| 15 min | ~900 | ~110 KB | ~90 KB |
| 30 min | ~1800 | ~220 KB | ~180 KB |
| 60 min | ~3600 | ~440 KB | ~360 KB |
| 3h (ultra) | ~10800 | ~1.3 MB | ~1.1 MB |

### Conversao Dart

```dart
/// Converte lista de pontos para JSON string pronta para upload.
String pointsToJson(List<LocationPointEntity> points) {
  final list = points.map((p) {
    final m = <String, Object>{'lat': p.lat, 'lng': p.lng, 'timestampMs': p.timestampMs};
    if (p.alt != null) m['alt'] = p.alt!;
    if (p.accuracy != null) m['accuracy'] = p.accuracy!;
    if (p.speed != null) m['speed'] = p.speed!;
    if (p.bearing != null) m['bearing'] = p.bearing!;
    return m;
  }).toList();
  return jsonEncode(list);
}
```

---

## 3. Session Metadata (Postgres)

### Destino

```
Supabase Postgres
Tabela:  public.sessions
Metodo:  UPSERT (on conflict session id)
```

### Payload JSON

Enviado como body do upsert via `supabase.from('sessions').upsert(...)`.

```json
{
  "id": "1707753600000",
  "user_id": "uuid-do-usuario",
  "status": 3,
  "start_time_ms": 1707753600000,
  "end_time_ms": 1707755400000,
  "total_distance_m": 5230.5,
  "moving_ms": 1620000,
  "is_verified": true,
  "integrity_flags": [],
  "ghost_session_id": null,
  "points_path": "uuid-do-usuario/1707753600000.json"
}

```

### Schema de campos

| Campo | Tipo | Obrigatorio | Unidade | Notas |
|---|---|---|---|---|
| id | string (UUID) | SIM | — | Mesmo que sessionUuid local |
| user_id | string (UUID) | SIM | — | auth.uid() do Supabase |
| status | integer | SIM | — | Ordinal de WorkoutStatus (3=completed) |
| start_time_ms | integer | SIM | milissegundos | Unix epoch UTC |
| end_time_ms | integer | NAO | milissegundos | Unix epoch UTC. Null se ativa |
| total_distance_m | number | SIM | metros | Distancia filtrada acumulada |
| moving_ms | integer | SIM | milissegundos | Tempo em movimento |
| is_verified | boolean | SIM | — | Anti-cheat passed |
| integrity_flags | string[] | SIM | — | Lista de flags (ex: ["HIGH_SPEED"]) |
| ghost_session_id | string | NAO | — | UUID da sessao ghost usada |
| points_path | string | NAO | — | Path no Storage bucket |

### Conversao Dart

```dart
/// Converte sessao local para Map pronto para upsert no Supabase.
Map<String, Object?> sessionToPayload(WorkoutSessionEntity s, String userId) {
  return {
    'id': s.id,
    'user_id': userId,
    'status': s.status.index,
    'start_time_ms': s.startTimeMs,
    'end_time_ms': s.endTimeMs,
    'total_distance_m': s.totalDistanceM ?? 0.0,
    'moving_ms': 0, // calculado localmente, a ser adicionado na entity
    'is_verified': s.isVerified,
    'integrity_flags': s.integrityFlags,
    'ghost_session_id': s.ghostSessionId,
    'points_path': '$userId/${s.id}.json',
  };
}
```

---

## 4. Politica de Upload

### Quando fazer upload

| Regra | Valor | Motivo |
|---|---|---|
| Trigger | Apos `FinishSession` com status `completed` | Sessoes incompletas/descartadas nao sao sincronizadas |
| Automatico | NAO (MVP) | Sync manual; usuario decide quando sincronizar |
| Retry | Sessoes `isSynced=false` sao re-tentadas no proximo sync | Resiliencia a falhas de rede |
| Batch | Uma sessao por vez, sequencial | Simplicidade; evita race conditions |

### Preferencia de rede

| Regra | Valor | Motivo |
|---|---|---|
| Wi-Fi preferido | SIM | Economizar dados moveis do corredor |
| Bloquear mobile data | NAO (MVP) | Usuario pode forcar sync em 4G se quiser |
| Check conectividade | SIM | Nao tentar upload se offline |
| Timeout por upload | 30 segundos | Evitar bloqueio em rede lenta |

### Implementacao sugerida (MVP)

```dart
/// Pseudo-codigo do fluxo de sync.
Future<void> syncPendingSessions() async {
  final pending = await sessionRepo.getUnsyncedCompleted();
  for (final session in pending) {
    try {
      // 1. Carregar pontos do Isar
      final points = await pointsRepo.getPoints(session.id);

      // 2. Upload pontos para Storage
      final path = '${userId}/${session.id}.json';
      final bytes = utf8.encode(pointsToJson(points));
      await supabase.storage
          .from('session-points')
          .uploadBinary(path, bytes, fileOptions: FileOptions(contentType: 'application/json'));

      // 3. Upsert metadados no Postgres
      await supabase.from('sessions').upsert(sessionToPayload(session, userId));

      // 4. Marcar como sincronizado localmente
      await sessionRepo.markSynced(session.id);
    } catch (e) {
      // Falhou — manter isSynced=false, tentar na proxima vez
      continue;
    }
  }
}
```

---

## 5. Ordem de Upload (Atomicidade)

```
ORDEM OBRIGATORIA:
  1. Upload points payload para Storage  (PRIMEIRO)
  2. Upsert session metadata no Postgres (SEGUNDO)
  3. Marcar isSynced = true localmente    (TERCEIRO)

MOTIVO:
  - Se (1) falha: nada foi escrito. Retry seguro.
  - Se (2) falha: points ficam orfaos no Storage.
    Aceitavel para MVP; cleanup futuro via cron/edge function.
  - Se (3) falha: sessao sera re-uploaded (idempotente via upsert).
    Storage overwrite e seguro. Postgres upsert e seguro.

GARANTIA:
  - Nenhum registro no Postgres aponta para points inexistentes
    (points sao uploaded antes do metadata).
  - Worst case: points orfaos no Storage (limpeza futura).
```

---

## 6. Seguranca

| Aspecto | Implementacao |
|---|---|
| Autenticacao | Bearer token JWT (Supabase Auth) em todo request |
| RLS (Postgres) | `auth.uid() = user_id` — usuario so ve/edita seus dados |
| Storage policy | `auth.uid()::text = folder_name` — usuario so acessa sua pasta |
| HTTPS | Obrigatorio (Supabase endpoints sao HTTPS por padrao) |
| Validacao server | Nenhuma no MVP (confianca no client). Pos-MVP: edge function para validar payload |

---

## 7. Versionamento do Payload

```
Versao atual: 1
Header de versao: NAO incluido no MVP (JSON puro, sem envelope)

Estrategia futura:
  - Se schema mudar, adicionar campo "version" no metadata da sessao
  - Points payload: adicionar campo "_v" no objeto raiz se mudar para
    formato diferente (ex: envelope com metadata + array)
  - Postgres: nova coluna ou migracao
  - Manter backward compatibility por pelo menos 2 versoes
```

---

## 8. Limites e Edge Cases

| Cenario | Tratamento |
|---|---|
| Sessao com 0 pontos | NAO sincronizar (skip) |
| Sessao > 10000 pontos (~3h) | Upload normal; ~1.1 MB e aceitavel |
| Sessao duplicada (re-sync) | Upsert e idempotente; Storage overwrite e seguro |
| Usuario deslogado | NAO sincronizar; acumular localmente |
| Falha de rede no meio | Retry na proxima chamada de sync |
| Storage cheio (free tier 1GB) | Erro capturado; notificar usuario |

---

*Documento gerado na Sprint 9.2*
