# OS-01 — App Flows: Treinos Prescritos

> **Atualizado:** 2026-03-04 — DECISAO 134/135

## Staff Flows

| # | Fluxo | Tela | Ação |
|---|-------|------|------|
| 1 | Ver agenda de treinos | `StaffTrainingListScreen` | Lista treinos com status, distância, contagem de concluídos |
| 2 | Criar treino com workout params | `StaffTrainingCreateScreen` | Título, descrição, local, data + **distância (km)**, **pace mín/máx** |
| 3 | Ver detalhe + cumprimento | `StaffTrainingDetailScreen` | Card do treino (distância, pace), lista de atletas com status colorido |
| 4 | Override manual | `StaffTrainingDetailScreen` | Toque no atleta → bottom sheet com opções de status |
| 5 | Cancelar treino | `StaffTrainingDetailScreen` | Menu popup → confirmar cancelamento |

## Athlete Flows

| # | Fluxo | Tela | Ação |
|---|-------|------|------|
| 1 | Ver treinos | `AthleteTrainingListScreen` | Lista próximos/anteriores com distância no card |
| 2 | Ver detalhes do treino | Bottom sheet | Distância, pace, local + badge de status (Concluído/Parcial/Ausente/Aguardando) |
| 3 | Ver histórico de treinos | `AthleteAttendanceScreen` | "Meus Treinos Prescritos" — lista de avaliações |

## Fluxos Removidos (DECISAO 134)

- ~~Atleta gera QR code~~ → `AthleteCheckinQrScreen` (navegação removida)
- ~~Staff escaneia QR~~ → `StaffTrainingScanScreen` (botão removido)

## Arquitetura

```
Entity → Repository → UseCase → BLoC → Screen
```

### Entities
- `TrainingSessionEntity` — inclui `distanceTargetM`, `paceMinSecKm`, `paceMaxSecKm`
- `TrainingAttendanceEntity` — inclui `matchedRunId`, `checkedBy` nullable, status `completed`/`partial`

### Repositories
| Interface | Implementação |
|-----------|---------------|
| `ITrainingSessionRepo` | `SupabaseTrainingSessionRepo` |
| `ITrainingAttendanceRepo` | `SupabaseTrainingAttendanceRepo` |

### Use Cases
| Use Case | Descrição |
|----------|-----------|
| `CreateTrainingSession` | Cria treino com workout params |
| `ListTrainingSessions` | Lista treinos do grupo |
| `CancelTrainingSession` | Cancela treino |
| `MarkAttendance` | Marca presença (legacy) |
| `IssueCheckinToken` | Gera token QR (legacy) |
| `ListAttendance` | Lista avaliações |

### BLoCs
| BLoC | Eventos |
|------|---------|
| `TrainingListBloc` | `LoadTrainingSessions`, `RefreshTrainingSessions` |
| `TrainingDetailBloc` | `LoadTrainingDetail`, `RefreshTrainingDetail`, `CancelTraining` |
| `CheckinBloc` | `GenerateCheckinQr`, `ConsumeCheckinQr` (legacy) |

### Screens
| Arquivo | Papel |
|---------|-------|
| `staff_training_list_screen.dart` | Agenda de treinos (staff) |
| `staff_training_create_screen.dart` | Criar/editar treino + workout params |
| `staff_training_detail_screen.dart` | Detalhe + cumprimento + override |
| `staff_training_scan_screen.dart` | Scanner QR (legacy, não navegado) |
| `athlete_training_list_screen.dart` | Lista de treinos (atleta) |
| `athlete_checkin_qr_screen.dart` | QR (legacy, não navegado) |
| `athlete_attendance_screen.dart` | "Meus Treinos Prescritos" |

## Labels (DECISAO 135)

| Contexto | Texto |
|----------|-------|
| Staff: header do detalhe | "Cumprimento do Treino (N)" |
| Staff: card na lista | "N atleta(s) concluíram" |
| Staff: tab no perfil do atleta | "Treinos" |
| Staff: form de criação | "O cumprimento do treino será avaliado automaticamente..." |
| Atleta: título da tela | "Meus Treinos Prescritos" |
| Atleta: mensagem vazia | "Seus resultados nos treinos prescritos aparecerão aqui." |

## Testes

- `test/domain/entities/training_entities_test.dart` — 17 testes (entidades, enums, labels)
- `test/domain/usecases/training/create_training_session_test.dart` — 10 testes (inclui workout params)
- `test/domain/usecases/training/mark_attendance_test.dart` — 4 testes
- `test/domain/usecases/training/list_training_sessions_test.dart` — 4 testes
- `test/domain/usecases/training/cancel_training_session_test.dart` — 3 testes
