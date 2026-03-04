# Cold Market Test — Fase 2: Primeira Abertura

> Simulação: usuário acabou de instalar o app pela primeira vez. Nunca viu nada sobre ele.

---

## 1. O que acontece no splash/launch?

O app **não tem splash screen customizada** (não existe `splash_screen.dart`). Usa o `LaunchScreen.storyboard` nativo do iOS e o `LaunchTheme` do Android — provavelmente uma tela branca com o ícone do Flutter ou uma tela em branco.

**Sequência de inicialização (main.dart):**

1. `WidgetsFlutterBinding.ensureInitialized()`
2. Configuração de error handlers globais
3. Sentry (crash reporting) — se configurado
4. Supabase init (backend)
5. Firebase init (push notifications)
6. Service locator setup
7. Deep link handler init
8. Foreground task config (GPS em background)
9. WearOS bridge init
10. Push notification service init
11. Auto-sync de sessões pendentes
12. Carregamento do tema (light/dark)
13. Verificação de sessão ativa para recovery
14. `runApp(OmniRunnerApp)` → `AuthGate`

**Tempo estimado de cold start:** 2-4 segundos (múltiplas inicializações de SDK assíncronas).

**Percepção do usuário:** Tela branca por alguns segundos, depois aparece o conteúdo. Não há indicação visual de carregamento durante o boot. Se o Supabase falhar, o app ainda abre (fallback para welcome screen).

**Nota:** O `flutter_native_splash` está nas dependências de dev, o que indica que há um splash nativo configurado, mas não há assets customizados declarados no `pubspec.yaml`. O splash provavelmente é minimalista.

---

## 2. O que o onboarding mostra?

O fluxo é controlado pelo `AuthGate`, que funciona como roteador baseado no estado do usuário:

### Passo 1: Welcome Screen
- Ícone de corredor animado (slide + fade)
- **Título:** "Seu app de corrida completo"
- **Subtítulo:** "Treinos, desafios, métricas e assessoria — tudo em um app."
- **4 bullets animados:**
  - "Corra com GPS preciso"
  - "Desafie outros corredores"
  - "Acompanhe sua evolução"
  - "Treine com assessoria ou sozinho"
- **CTA:** Botão "COMEÇAR" (FilledButton, full-width)
- Animação total: ~1.4 segundos (escalonada)

### Passo 2: Login Screen
- Header: ícone de corredor + "Entrar no Omni Runner"
- Subtítulo: "Use sua conta para sincronizar treinos, desafios e progresso entre dispositivos."
- Banner de convite pendente (se aplicável)
- **Opções de login:**
  - Google (sempre visível)
  - Apple (apenas iOS)
  - Instagram (via Meta OAuth)
  - Email/senha (expansível)
- Link para Política de Privacidade
- Funcionalidade de "Esqueci a senha" e "Criar conta"

### Passo 3: Seleção de Papel (OnboardingRoleScreen)
- **Pergunta:** "Como você quer usar o Omni Runner?"
- **Duas opções:**
  - "Sou atleta" → Treinar, competir em desafios e acompanhar evolução
  - "Represento uma assessoria" → Gerenciar atletas, organizar eventos
- Botão de confirmação com diálogo explicativo
- Nota: "Você pode ajustar isso depois em Configurações."
- Botão "Voltar para o login" disponível

### Passo 4a (Atleta): Join Assessoria Screen
- **Título:** "Encontre sua assessoria"
- **Explicação:** "Assessoria é seu grupo de corrida com treinador."
- **4 formas de entrar:**
  1. Buscar por nome (campo de pesquisa com debounce)
  2. Escanear QR code
  3. Digitar código manualmente
  4. **Pular** ("Pular — posso entrar depois")
- Nota ao pular: "Você pode usar o app normalmente. Assessoria desbloqueia ranking de grupo e desafios em equipe."

### Passo 4b (Staff): Staff Setup Screen
- Fluxo separado para configurar a assessoria

### Passo 5: Tour Guiado (OnboardingTourScreen)
- **9 slides swipeable:**
  1. Conecte seu Strava
  2. Desafie outros corredores
  3. Treine com sua assessoria
  4. Mantenha sua sequência (streaks)
  5. Acompanhe sua evolução
  6. Encontre amigos
  7. Desafie seus amigos (3 tipos de desafio)
  8. OmniCoins
  9. Atleta Verificado
- Botão "Pular" disponível em todas as telas
- CTA muda de "PRÓXIMO" para "COMEÇAR A CORRER" no último slide
- Indicador de progresso (dots)

---

## 3. O app explica seu valor?

### Sim, mas de forma fragmentada e longa.

**Pontos positivos:**
- A welcome screen é concisa e comunica 4 benefícios em 4 segundos
- O tour de 9 slides cobre todas as funcionalidades-chave
- Cada slide do tour tem título + descrição clara

**Pontos negativos:**
- O tour tem **9 slides** — é excessivo. A maioria dos usuários vai pular
- O valor central ("desafiar outros corredores com moeda virtual") se perde no meio de muita informação
- O conceito de "assessoria" não é explicado na welcome screen — aparece primeiro como bullet genérico ("Treine com assessoria ou sozinho") e só é explicado no JoinAssessoria ("Assessoria é seu grupo de corrida com treinador")
- O app não mostra NENHUM resultado real antes do login — não há preview de dados, screenshots internas, ou exemplos visuais
- A comunicação de valor depende do usuário ler texto — não há demonstrações visuais

**Veredicto:** O app explica *o que faz*, mas não demonstra *por que o usuário deveria se importar*. Falta o "momento aha" visual.

---

## 4. O usuário sabe o que fazer em seguida?

### Em cada etapa:

| Etapa | Clareza da ação seguinte |
|---|---|
| Welcome Screen | ✅ Claro — botão "COMEÇAR" óbvio |
| Login Screen | ✅ Claro — 3-4 botões de login visíveis |
| Seleção de Papel | ✅ Claro — duas opções + "Continuar" |
| Join Assessoria | ⚠️ Moderado — 4 opções + "Pular", pode ser confuso para quem não tem assessoria |
| Tour | ✅ Claro — "PRÓXIMO" / "COMEÇAR A CORRER" |
| Home Screen | ⚠️ Moderado — muitos cards, não há hierarquia clara de "faça isso primeiro" |

**Problema-chave:** No JoinAssessoria, o usuário que NÃO tem assessoria fica confuso. A tela assume que a maioria dos usuários tem assessoria. O botão "Pular" está no final da tela e parece uma opção inferior. Para o corredor casual/solo, essa tela é uma barreira desnecessária.

---

## 5. Que permissões são solicitadas e quando?

### Permissões declaradas no AndroidManifest:

| Permissão | Quando é solicitada |
|---|---|
| `INTERNET` | Implícita (sem popup) |
| `ACCESS_FINE_LOCATION` | Ao iniciar uma corrida com GPS |
| `ACCESS_COARSE_LOCATION` | Junto com fine location |
| `ACCESS_BACKGROUND_LOCATION` | Ao usar GPS em segundo plano (durante corrida) |
| `FOREGROUND_SERVICE` / `FOREGROUND_SERVICE_LOCATION` | Implícita (para manter GPS ativo) |
| `BLUETOOTH_SCAN` / `BLUETOOTH_CONNECT` | Ao conectar monitor cardíaco BLE |
| Health Connect (HR, Steps, Exercise, Distance, Calories) | Ao abrir integração com saúde |
| `ACTIVITY_RECOGNITION` | Detecção de atividade física |
| Câmera | Ao editar foto de perfil |

### Permissões no iOS (Info.plist):

| Permissão | Descrição apresentada ao usuário |
|---|---|
| Location (When In Use) | "Omni Runner needs your location to record your running route, calculate distance and pace in real time." |
| Location (Always) | "Omni Runner needs your location in the background to continue recording your run when the app is minimized." |
| HealthKit (Share) | Leitura de HR, steps, workout data |
| HealthKit (Update) | Salvar corridas no Apple Health |
| Bluetooth | Conectar monitores cardíacos BLE |
| Câmera | Capturar foto de perfil |
| Fotos | Definir foto de perfil |

### Análise do timing de permissões:

**Ponto positivo:** As permissões NÃO são solicitadas durante o onboarding. O app usa `permission_handler` e solicita contextualmente (quando o usuário tenta usar a funcionalidade que requer a permissão). Isso é uma boa prática.

**Ponto negativo:** A string de localização do iOS está em inglês enquanto o app é em português — inconsistência que pode confundir. As strings de câmera/foto estão parcialmente em português.

---

## 6. Avaliações

### Clareza: 6/10

O fluxo é lógico e sequencial, mas tem pontos de confusão:
- "Assessoria" não é explicada cedo o suficiente
- A tela de login não deixa claro que o app pode funcionar sem conta (modo offline existe mas não é apresentado)
- O tour de 9 slides é informação demais para absorver

### Comunicação de Valor: 5/10

A welcome screen é boa (4 bullets), mas o app não demonstra valor visualmente. Não há:
- Prévia do dashboard
- Exemplo de desafio
- Demonstração de como o Strava se integra
- Nenhum "antes e depois" ou social proof

O usuário precisa completar 5 passos (welcome → login → role → assessoria → tour) antes de ver qualquer funcionalidade real. São ~2-3 minutos de onboarding puro.

### Fricção: 7/10 (alta fricção)

| Fonte de fricção | Severidade |
|---|---|
| Login obrigatório antes de ver qualquer funcionalidade | 🔴 Alta |
| Seleção de papel (atleta vs assessoria) logo após login | 🟡 Média |
| Tela de "encontre sua assessoria" para quem não tem | 🔴 Alta |
| Tour de 9 slides | 🟡 Média (tem "Pular") |
| Necessidade de conectar Strava antes do primeiro uso real | 🔴 Alta |
| Total de telas antes de ver a home: 4-5 | 🔴 Alta |

**Comparação:** O Strava permite que o usuário grave uma corrida em 2 toques após instalar. O Nike Run Club mostra funcionalidades sem login. O Omni Runner exige login, seleção de papel, decisão sobre assessoria e tour antes de mostrar qualquer tela funcional.

---

## Resumo Executivo

O onboarding do Omni Runner é **completo mas excessivamente longo**. Ele cobre bem as funcionalidades, mas prioriza explicação sobre experiência. O corredor casual pode desistir antes de chegar à home screen.

**Recomendações-chave (se fosse para corrigir):**
1. Permitir explorar o app sem login (modo "guest")
2. Reduzir o tour de 9 para 3-4 slides focados no diferencial
3. Mover a tela de assessoria para depois da primeira corrida
4. Mostrar um preview visual do dashboard na welcome screen
5. Corrigir strings de permissão para português consistente
