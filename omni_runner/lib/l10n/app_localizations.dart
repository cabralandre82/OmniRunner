import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_pt.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('pt'),
  ];

  /// App title shown in the app bar
  ///
  /// In pt, this message translates to:
  /// **'Omni Runner'**
  String get appTitle;

  /// No description provided for @dashboard.
  ///
  /// In pt, this message translates to:
  /// **'Início'**
  String get dashboard;

  /// No description provided for @runs.
  ///
  /// In pt, this message translates to:
  /// **'Corridas'**
  String get runs;

  /// No description provided for @challenges.
  ///
  /// In pt, this message translates to:
  /// **'Desafios'**
  String get challenges;

  /// No description provided for @social.
  ///
  /// In pt, this message translates to:
  /// **'Social'**
  String get social;

  /// No description provided for @profile.
  ///
  /// In pt, this message translates to:
  /// **'Perfil'**
  String get profile;

  /// No description provided for @settings.
  ///
  /// In pt, this message translates to:
  /// **'Configurações'**
  String get settings;

  /// No description provided for @more.
  ///
  /// In pt, this message translates to:
  /// **'Mais'**
  String get more;

  /// No description provided for @history.
  ///
  /// In pt, this message translates to:
  /// **'Histórico'**
  String get history;

  /// No description provided for @progression.
  ///
  /// In pt, this message translates to:
  /// **'Progressão'**
  String get progression;

  /// No description provided for @wallet.
  ///
  /// In pt, this message translates to:
  /// **'Carteira'**
  String get wallet;

  /// No description provided for @leaderboards.
  ///
  /// In pt, this message translates to:
  /// **'Rankings'**
  String get leaderboards;

  /// No description provided for @verification.
  ///
  /// In pt, this message translates to:
  /// **'Verificação'**
  String get verification;

  /// No description provided for @diagnostics.
  ///
  /// In pt, this message translates to:
  /// **'Diagnóstico'**
  String get diagnostics;

  /// No description provided for @support.
  ///
  /// In pt, this message translates to:
  /// **'Suporte'**
  String get support;

  /// No description provided for @howItWorks.
  ///
  /// In pt, this message translates to:
  /// **'Como funciona'**
  String get howItWorks;

  /// No description provided for @startRun.
  ///
  /// In pt, this message translates to:
  /// **'Iniciar corrida'**
  String get startRun;

  /// No description provided for @stopRun.
  ///
  /// In pt, this message translates to:
  /// **'Parar corrida'**
  String get stopRun;

  /// No description provided for @pauseRun.
  ///
  /// In pt, this message translates to:
  /// **'Pausar corrida'**
  String get pauseRun;

  /// No description provided for @resumeRun.
  ///
  /// In pt, this message translates to:
  /// **'Retomar corrida'**
  String get resumeRun;

  /// No description provided for @finishRun.
  ///
  /// In pt, this message translates to:
  /// **'Finalizar corrida'**
  String get finishRun;

  /// No description provided for @discardRun.
  ///
  /// In pt, this message translates to:
  /// **'Descartar corrida'**
  String get discardRun;

  /// No description provided for @runSummary.
  ///
  /// In pt, this message translates to:
  /// **'Resumo da corrida'**
  String get runSummary;

  /// No description provided for @replay.
  ///
  /// In pt, this message translates to:
  /// **'Replay da corrida'**
  String get replay;

  /// No description provided for @gpsPoints.
  ///
  /// In pt, this message translates to:
  /// **'{count} pontos GPS registrados'**
  String gpsPoints(int count);

  /// No description provided for @distance.
  ///
  /// In pt, this message translates to:
  /// **'Distância'**
  String get distance;

  /// No description provided for @pace.
  ///
  /// In pt, this message translates to:
  /// **'Ritmo'**
  String get pace;

  /// No description provided for @avgPace.
  ///
  /// In pt, this message translates to:
  /// **'Pace médio'**
  String get avgPace;

  /// No description provided for @duration.
  ///
  /// In pt, this message translates to:
  /// **'Duração'**
  String get duration;

  /// No description provided for @calories.
  ///
  /// In pt, this message translates to:
  /// **'Calorias'**
  String get calories;

  /// No description provided for @elevation.
  ///
  /// In pt, this message translates to:
  /// **'Elevação'**
  String get elevation;

  /// No description provided for @heartRate.
  ///
  /// In pt, this message translates to:
  /// **'Freq. Cardíaca'**
  String get heartRate;

  /// No description provided for @avgHeartRate.
  ///
  /// In pt, this message translates to:
  /// **'FC média'**
  String get avgHeartRate;

  /// No description provided for @maxHeartRate.
  ///
  /// In pt, this message translates to:
  /// **'FC máx'**
  String get maxHeartRate;

  /// No description provided for @cadence.
  ///
  /// In pt, this message translates to:
  /// **'Cadência'**
  String get cadence;

  /// No description provided for @km.
  ///
  /// In pt, this message translates to:
  /// **'km'**
  String get km;

  /// No description provided for @minPerKm.
  ///
  /// In pt, this message translates to:
  /// **'min/km'**
  String get minPerKm;

  /// No description provided for @bpm.
  ///
  /// In pt, this message translates to:
  /// **'bpm'**
  String get bpm;

  /// No description provided for @today.
  ///
  /// In pt, this message translates to:
  /// **'Hoje'**
  String get today;

  /// No description provided for @thisWeek.
  ///
  /// In pt, this message translates to:
  /// **'Esta semana'**
  String get thisWeek;

  /// No description provided for @thisMonth.
  ///
  /// In pt, this message translates to:
  /// **'Este mês'**
  String get thisMonth;

  /// No description provided for @allTime.
  ///
  /// In pt, this message translates to:
  /// **'Total'**
  String get allTime;

  /// No description provided for @daily.
  ///
  /// In pt, this message translates to:
  /// **'Diário'**
  String get daily;

  /// No description provided for @weekly.
  ///
  /// In pt, this message translates to:
  /// **'Semanal'**
  String get weekly;

  /// No description provided for @monthly.
  ///
  /// In pt, this message translates to:
  /// **'Mensal'**
  String get monthly;

  /// No description provided for @noRunsYet.
  ///
  /// In pt, this message translates to:
  /// **'Nenhuma corrida ainda'**
  String get noRunsYet;

  /// No description provided for @noRunsYetDescription.
  ///
  /// In pt, this message translates to:
  /// **'Comece sua primeira corrida e acompanhe sua evolução!'**
  String get noRunsYetDescription;

  /// No description provided for @noDataYet.
  ///
  /// In pt, this message translates to:
  /// **'Nenhum dado ainda'**
  String get noDataYet;

  /// No description provided for @noResultsFound.
  ///
  /// In pt, this message translates to:
  /// **'Nenhum resultado encontrado'**
  String get noResultsFound;

  /// No description provided for @noChallengesYet.
  ///
  /// In pt, this message translates to:
  /// **'Nenhum desafio ativo'**
  String get noChallengesYet;

  /// No description provided for @noChallengesYetDescription.
  ///
  /// In pt, this message translates to:
  /// **'Crie ou aceite um desafio para competir com amigos.'**
  String get noChallengesYetDescription;

  /// No description provided for @challengeDetails.
  ///
  /// In pt, this message translates to:
  /// **'Detalhes do desafio'**
  String get challengeDetails;

  /// No description provided for @createChallenge.
  ///
  /// In pt, this message translates to:
  /// **'Criar desafio'**
  String get createChallenge;

  /// No description provided for @joinChallenge.
  ///
  /// In pt, this message translates to:
  /// **'Entrar no desafio'**
  String get joinChallenge;

  /// No description provided for @challengeActive.
  ///
  /// In pt, this message translates to:
  /// **'Ativo'**
  String get challengeActive;

  /// No description provided for @challengeCompleted.
  ///
  /// In pt, this message translates to:
  /// **'Concluído'**
  String get challengeCompleted;

  /// No description provided for @challengePending.
  ///
  /// In pt, this message translates to:
  /// **'Pendente'**
  String get challengePending;

  /// No description provided for @challengeCancelled.
  ///
  /// In pt, this message translates to:
  /// **'Cancelado'**
  String get challengeCancelled;

  /// No description provided for @challengeExpired.
  ///
  /// In pt, this message translates to:
  /// **'Expirado'**
  String get challengeExpired;

  /// No description provided for @groups.
  ///
  /// In pt, this message translates to:
  /// **'Grupos'**
  String get groups;

  /// No description provided for @events.
  ///
  /// In pt, this message translates to:
  /// **'Eventos'**
  String get events;

  /// No description provided for @friends.
  ///
  /// In pt, this message translates to:
  /// **'Amigos'**
  String get friends;

  /// No description provided for @members.
  ///
  /// In pt, this message translates to:
  /// **'Membros'**
  String get members;

  /// No description provided for @rankings.
  ///
  /// In pt, this message translates to:
  /// **'Rankings'**
  String get rankings;

  /// No description provided for @createGroup.
  ///
  /// In pt, this message translates to:
  /// **'Criar grupo'**
  String get createGroup;

  /// No description provided for @joinGroup.
  ///
  /// In pt, this message translates to:
  /// **'Entrar no grupo'**
  String get joinGroup;

  /// No description provided for @leaveGroup.
  ///
  /// In pt, this message translates to:
  /// **'Sair do grupo'**
  String get leaveGroup;

  /// No description provided for @groupDetails.
  ///
  /// In pt, this message translates to:
  /// **'Detalhes do grupo'**
  String get groupDetails;

  /// No description provided for @inviteCode.
  ///
  /// In pt, this message translates to:
  /// **'Código de convite'**
  String get inviteCode;

  /// No description provided for @coins.
  ///
  /// In pt, this message translates to:
  /// **'Moedas'**
  String get coins;

  /// No description provided for @xp.
  ///
  /// In pt, this message translates to:
  /// **'XP'**
  String get xp;

  /// No description provided for @level.
  ///
  /// In pt, this message translates to:
  /// **'Nível'**
  String get level;

  /// No description provided for @badges.
  ///
  /// In pt, this message translates to:
  /// **'Conquistas'**
  String get badges;

  /// No description provided for @missions.
  ///
  /// In pt, this message translates to:
  /// **'Missões'**
  String get missions;

  /// No description provided for @streak.
  ///
  /// In pt, this message translates to:
  /// **'Sequência'**
  String get streak;

  /// No description provided for @streakDays.
  ///
  /// In pt, this message translates to:
  /// **'{count} dias'**
  String streakDays(int count);

  /// No description provided for @coaching.
  ///
  /// In pt, this message translates to:
  /// **'Assessoria'**
  String get coaching;

  /// No description provided for @myCoach.
  ///
  /// In pt, this message translates to:
  /// **'Minha assessoria'**
  String get myCoach;

  /// No description provided for @switchCoach.
  ///
  /// In pt, this message translates to:
  /// **'Trocar assessoria'**
  String get switchCoach;

  /// No description provided for @joinCoach.
  ///
  /// In pt, this message translates to:
  /// **'Entrar em assessoria'**
  String get joinCoach;

  /// No description provided for @coachInsights.
  ///
  /// In pt, this message translates to:
  /// **'Insights'**
  String get coachInsights;

  /// No description provided for @athleteEvolution.
  ///
  /// In pt, this message translates to:
  /// **'Evolução do atleta'**
  String get athleteEvolution;

  /// No description provided for @groupEvolution.
  ///
  /// In pt, this message translates to:
  /// **'Evolução do grupo'**
  String get groupEvolution;

  /// No description provided for @errorGeneric.
  ///
  /// In pt, this message translates to:
  /// **'Algo deu errado. Tente novamente.'**
  String get errorGeneric;

  /// No description provided for @errorNoConnection.
  ///
  /// In pt, this message translates to:
  /// **'Sem conexão com a internet.'**
  String get errorNoConnection;

  /// No description provided for @errorNoConnectionDetailed.
  ///
  /// In pt, this message translates to:
  /// **'Sem conexão com a internet. Alguns recursos podem não funcionar.'**
  String get errorNoConnectionDetailed;

  /// No description provided for @errorSessionExpired.
  ///
  /// In pt, this message translates to:
  /// **'Sua sessão expirou. Faça login novamente.'**
  String get errorSessionExpired;

  /// No description provided for @errorForbidden.
  ///
  /// In pt, this message translates to:
  /// **'Você não tem permissão para esta ação.'**
  String get errorForbidden;

  /// No description provided for @errorNotFound.
  ///
  /// In pt, this message translates to:
  /// **'O conteúdo não foi encontrado.'**
  String get errorNotFound;

  /// No description provided for @errorServer.
  ///
  /// In pt, this message translates to:
  /// **'Erro no servidor. Tente novamente em alguns minutos.'**
  String get errorServer;

  /// No description provided for @errorTimeout.
  ///
  /// In pt, this message translates to:
  /// **'A requisição demorou demais. Tente novamente.'**
  String get errorTimeout;

  /// No description provided for @retry.
  ///
  /// In pt, this message translates to:
  /// **'Tentar novamente'**
  String get retry;

  /// No description provided for @cancel.
  ///
  /// In pt, this message translates to:
  /// **'Cancelar'**
  String get cancel;

  /// No description provided for @save.
  ///
  /// In pt, this message translates to:
  /// **'Salvar'**
  String get save;

  /// No description provided for @delete.
  ///
  /// In pt, this message translates to:
  /// **'Excluir'**
  String get delete;

  /// No description provided for @confirm.
  ///
  /// In pt, this message translates to:
  /// **'Confirmar'**
  String get confirm;

  /// No description provided for @close.
  ///
  /// In pt, this message translates to:
  /// **'Fechar'**
  String get close;

  /// No description provided for @done.
  ///
  /// In pt, this message translates to:
  /// **'Concluído'**
  String get done;

  /// No description provided for @next.
  ///
  /// In pt, this message translates to:
  /// **'Próximo'**
  String get next;

  /// No description provided for @back.
  ///
  /// In pt, this message translates to:
  /// **'Voltar'**
  String get back;

  /// No description provided for @loading.
  ///
  /// In pt, this message translates to:
  /// **'Carregando...'**
  String get loading;

  /// No description provided for @loadingContent.
  ///
  /// In pt, this message translates to:
  /// **'Carregando conteúdo'**
  String get loadingContent;

  /// No description provided for @search.
  ///
  /// In pt, this message translates to:
  /// **'Buscar'**
  String get search;

  /// No description provided for @share.
  ///
  /// In pt, this message translates to:
  /// **'Compartilhar'**
  String get share;

  /// No description provided for @copy.
  ///
  /// In pt, this message translates to:
  /// **'Copiar'**
  String get copy;

  /// No description provided for @copied.
  ///
  /// In pt, this message translates to:
  /// **'Copiado!'**
  String get copied;

  /// No description provided for @edit.
  ///
  /// In pt, this message translates to:
  /// **'Editar'**
  String get edit;

  /// No description provided for @add.
  ///
  /// In pt, this message translates to:
  /// **'Adicionar'**
  String get add;

  /// No description provided for @remove.
  ///
  /// In pt, this message translates to:
  /// **'Remover'**
  String get remove;

  /// No description provided for @refresh.
  ///
  /// In pt, this message translates to:
  /// **'Atualizar'**
  String get refresh;

  /// No description provided for @seeAll.
  ///
  /// In pt, this message translates to:
  /// **'Ver tudo'**
  String get seeAll;

  /// No description provided for @seeMore.
  ///
  /// In pt, this message translates to:
  /// **'Ver mais'**
  String get seeMore;

  /// No description provided for @darkMode.
  ///
  /// In pt, this message translates to:
  /// **'Modo escuro'**
  String get darkMode;

  /// No description provided for @lightMode.
  ///
  /// In pt, this message translates to:
  /// **'Modo claro'**
  String get lightMode;

  /// No description provided for @systemMode.
  ///
  /// In pt, this message translates to:
  /// **'Seguir sistema'**
  String get systemMode;

  /// No description provided for @theme.
  ///
  /// In pt, this message translates to:
  /// **'Tema'**
  String get theme;

  /// No description provided for @audioCoach.
  ///
  /// In pt, this message translates to:
  /// **'Treinador de áudio'**
  String get audioCoach;

  /// No description provided for @notifications.
  ///
  /// In pt, this message translates to:
  /// **'Notificações'**
  String get notifications;

  /// No description provided for @privacy.
  ///
  /// In pt, this message translates to:
  /// **'Privacidade'**
  String get privacy;

  /// No description provided for @account.
  ///
  /// In pt, this message translates to:
  /// **'Conta'**
  String get account;

  /// No description provided for @about.
  ///
  /// In pt, this message translates to:
  /// **'Sobre'**
  String get about;

  /// No description provided for @version.
  ///
  /// In pt, this message translates to:
  /// **'Versão'**
  String get version;

  /// No description provided for @logout.
  ///
  /// In pt, this message translates to:
  /// **'Sair'**
  String get logout;

  /// No description provided for @logoutConfirm.
  ///
  /// In pt, this message translates to:
  /// **'Tem certeza que deseja sair?'**
  String get logoutConfirm;

  /// No description provided for @login.
  ///
  /// In pt, this message translates to:
  /// **'Entrar'**
  String get login;

  /// No description provided for @signUp.
  ///
  /// In pt, this message translates to:
  /// **'Criar conta'**
  String get signUp;

  /// No description provided for @continueWithGoogle.
  ///
  /// In pt, this message translates to:
  /// **'Continuar com Google'**
  String get continueWithGoogle;

  /// No description provided for @continueWithApple.
  ///
  /// In pt, this message translates to:
  /// **'Continuar com Apple'**
  String get continueWithApple;

  /// No description provided for @welcomeBack.
  ///
  /// In pt, this message translates to:
  /// **'Bem-vindo de volta!'**
  String get welcomeBack;

  /// No description provided for @verified.
  ///
  /// In pt, this message translates to:
  /// **'Verificado'**
  String get verified;

  /// No description provided for @unverified.
  ///
  /// In pt, this message translates to:
  /// **'Não verificado'**
  String get unverified;

  /// No description provided for @pending.
  ///
  /// In pt, this message translates to:
  /// **'Pendente'**
  String get pending;

  /// No description provided for @approved.
  ///
  /// In pt, this message translates to:
  /// **'Aprovado'**
  String get approved;

  /// No description provided for @rejected.
  ///
  /// In pt, this message translates to:
  /// **'Rejeitado'**
  String get rejected;

  /// No description provided for @suspended.
  ///
  /// In pt, this message translates to:
  /// **'Suspenso'**
  String get suspended;

  /// No description provided for @personalRecord.
  ///
  /// In pt, this message translates to:
  /// **'Recorde pessoal'**
  String get personalRecord;

  /// No description provided for @newRecord.
  ///
  /// In pt, this message translates to:
  /// **'Novo recorde!'**
  String get newRecord;

  /// No description provided for @bestPace.
  ///
  /// In pt, this message translates to:
  /// **'Melhor pace'**
  String get bestPace;

  /// No description provided for @longestRun.
  ///
  /// In pt, this message translates to:
  /// **'Maior distância'**
  String get longestRun;

  /// No description provided for @totalSessions.
  ///
  /// In pt, this message translates to:
  /// **'Total de sessões'**
  String get totalSessions;

  /// No description provided for @totalDistance.
  ///
  /// In pt, this message translates to:
  /// **'Distância total'**
  String get totalDistance;

  /// No description provided for @recoverSession.
  ///
  /// In pt, this message translates to:
  /// **'Recuperar sessão'**
  String get recoverSession;

  /// No description provided for @recoverSessionDescription.
  ///
  /// In pt, this message translates to:
  /// **'Uma sessão anterior não foi finalizada. Deseja recuperá-la?'**
  String get recoverSessionDescription;

  /// No description provided for @resumeSession.
  ///
  /// In pt, this message translates to:
  /// **'Retomar'**
  String get resumeSession;

  /// No description provided for @discardSession.
  ///
  /// In pt, this message translates to:
  /// **'Descartar'**
  String get discardSession;

  /// No description provided for @distanceFormatKm.
  ///
  /// In pt, this message translates to:
  /// **'{distance} km'**
  String distanceFormatKm(String distance);

  /// No description provided for @paceFormat.
  ///
  /// In pt, this message translates to:
  /// **'{pace} min/km'**
  String paceFormat(String pace);

  /// No description provided for @levelFormat.
  ///
  /// In pt, this message translates to:
  /// **'Nível {level}'**
  String levelFormat(int level);

  /// No description provided for @coinsFormat.
  ///
  /// In pt, this message translates to:
  /// **'{count} moedas'**
  String coinsFormat(int count);

  /// No description provided for @sessionCount.
  ///
  /// In pt, this message translates to:
  /// **'{count, plural, =0{Nenhuma sessão} =1{1 sessão} other{{count} sessões}}'**
  String sessionCount(int count);

  /// No description provided for @myAssessoria.
  ///
  /// In pt, this message translates to:
  /// **'Minha Assessoria'**
  String get myAssessoria;

  /// No description provided for @switchAssessoria.
  ///
  /// In pt, this message translates to:
  /// **'Trocar de Assessoria'**
  String get switchAssessoria;

  /// No description provided for @assessoriaFeed.
  ///
  /// In pt, this message translates to:
  /// **'Feed da Assessoria'**
  String get assessoriaFeed;

  /// No description provided for @consistency.
  ///
  /// In pt, this message translates to:
  /// **'Consistência'**
  String get consistency;

  /// No description provided for @myEvolution.
  ///
  /// In pt, this message translates to:
  /// **'Minha Evolução'**
  String get myEvolution;

  /// No description provided for @myRunnerDna.
  ///
  /// In pt, this message translates to:
  /// **'Meu DNA de Corredor'**
  String get myRunnerDna;

  /// No description provided for @assessoriaLeague.
  ///
  /// In pt, this message translates to:
  /// **'Liga de Assessorias'**
  String get assessoriaLeague;

  /// No description provided for @newTicket.
  ///
  /// In pt, this message translates to:
  /// **'Novo chamado'**
  String get newTicket;

  /// No description provided for @runDetails.
  ///
  /// In pt, this message translates to:
  /// **'Detalhes da corrida'**
  String get runDetails;

  /// No description provided for @inviteFriends.
  ///
  /// In pt, this message translates to:
  /// **'Convidar amigos'**
  String get inviteFriends;

  /// No description provided for @myFriends.
  ///
  /// In pt, this message translates to:
  /// **'Meus Amigos'**
  String get myFriends;

  /// No description provided for @wrapped.
  ///
  /// In pt, this message translates to:
  /// **'Retrospectiva'**
  String get wrapped;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'pt'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'pt':
      return AppLocalizationsPt();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
