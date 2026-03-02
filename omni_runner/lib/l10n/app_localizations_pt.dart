// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Portuguese (`pt`).
class AppLocalizationsPt extends AppLocalizations {
  AppLocalizationsPt([String locale = 'pt']) : super(locale);

  @override
  String get appTitle => 'Omni Runner';

  @override
  String get dashboard => 'Início';

  @override
  String get runs => 'Corridas';

  @override
  String get challenges => 'Desafios';

  @override
  String get social => 'Social';

  @override
  String get profile => 'Perfil';

  @override
  String get settings => 'Configurações';

  @override
  String get more => 'Mais';

  @override
  String get history => 'Histórico';

  @override
  String get progression => 'Progressão';

  @override
  String get wallet => 'Carteira';

  @override
  String get leaderboards => 'Rankings';

  @override
  String get verification => 'Verificação';

  @override
  String get diagnostics => 'Diagnóstico';

  @override
  String get support => 'Suporte';

  @override
  String get howItWorks => 'Como funciona';

  @override
  String get startRun => 'Iniciar corrida';

  @override
  String get stopRun => 'Parar corrida';

  @override
  String get pauseRun => 'Pausar corrida';

  @override
  String get resumeRun => 'Retomar corrida';

  @override
  String get finishRun => 'Finalizar corrida';

  @override
  String get discardRun => 'Descartar corrida';

  @override
  String get runSummary => 'Resumo da corrida';

  @override
  String get replay => 'Replay da corrida';

  @override
  String gpsPoints(int count) {
    return '$count pontos GPS registrados';
  }

  @override
  String get distance => 'Distância';

  @override
  String get pace => 'Ritmo';

  @override
  String get avgPace => 'Pace médio';

  @override
  String get duration => 'Duração';

  @override
  String get calories => 'Calorias';

  @override
  String get elevation => 'Elevação';

  @override
  String get heartRate => 'Freq. Cardíaca';

  @override
  String get avgHeartRate => 'FC média';

  @override
  String get maxHeartRate => 'FC máx';

  @override
  String get cadence => 'Cadência';

  @override
  String get km => 'km';

  @override
  String get minPerKm => 'min/km';

  @override
  String get bpm => 'bpm';

  @override
  String get today => 'Hoje';

  @override
  String get thisWeek => 'Esta semana';

  @override
  String get thisMonth => 'Este mês';

  @override
  String get allTime => 'Total';

  @override
  String get daily => 'Diário';

  @override
  String get weekly => 'Semanal';

  @override
  String get monthly => 'Mensal';

  @override
  String get noRunsYet => 'Nenhuma corrida ainda';

  @override
  String get noRunsYetDescription =>
      'Comece sua primeira corrida e acompanhe sua evolução!';

  @override
  String get noDataYet => 'Nenhum dado ainda';

  @override
  String get noResultsFound => 'Nenhum resultado encontrado';

  @override
  String get noChallengesYet => 'Nenhum desafio ativo';

  @override
  String get noChallengesYetDescription =>
      'Crie ou aceite um desafio para competir com amigos.';

  @override
  String get challengeDetails => 'Detalhes do desafio';

  @override
  String get createChallenge => 'Criar desafio';

  @override
  String get joinChallenge => 'Entrar no desafio';

  @override
  String get challengeActive => 'Ativo';

  @override
  String get challengeCompleted => 'Concluído';

  @override
  String get challengePending => 'Pendente';

  @override
  String get challengeCancelled => 'Cancelado';

  @override
  String get challengeExpired => 'Expirado';

  @override
  String get groups => 'Grupos';

  @override
  String get events => 'Eventos';

  @override
  String get friends => 'Amigos';

  @override
  String get members => 'Membros';

  @override
  String get rankings => 'Rankings';

  @override
  String get createGroup => 'Criar grupo';

  @override
  String get joinGroup => 'Entrar no grupo';

  @override
  String get leaveGroup => 'Sair do grupo';

  @override
  String get groupDetails => 'Detalhes do grupo';

  @override
  String get inviteCode => 'Código de convite';

  @override
  String get coins => 'Moedas';

  @override
  String get xp => 'XP';

  @override
  String get level => 'Nível';

  @override
  String get badges => 'Conquistas';

  @override
  String get missions => 'Missões';

  @override
  String get streak => 'Sequência';

  @override
  String streakDays(int count) {
    return '$count dias';
  }

  @override
  String get coaching => 'Assessoria';

  @override
  String get myCoach => 'Minha assessoria';

  @override
  String get switchCoach => 'Trocar assessoria';

  @override
  String get joinCoach => 'Entrar em assessoria';

  @override
  String get coachInsights => 'Insights';

  @override
  String get athleteEvolution => 'Evolução do atleta';

  @override
  String get groupEvolution => 'Evolução do grupo';

  @override
  String get errorGeneric => 'Algo deu errado. Tente novamente.';

  @override
  String get errorNoConnection => 'Sem conexão com a internet.';

  @override
  String get errorNoConnectionDetailed =>
      'Sem conexão com a internet. Alguns recursos podem não funcionar.';

  @override
  String get errorSessionExpired => 'Sua sessão expirou. Faça login novamente.';

  @override
  String get errorForbidden => 'Você não tem permissão para esta ação.';

  @override
  String get errorNotFound => 'O conteúdo não foi encontrado.';

  @override
  String get errorServer =>
      'Erro no servidor. Tente novamente em alguns minutos.';

  @override
  String get errorTimeout => 'A requisição demorou demais. Tente novamente.';

  @override
  String get retry => 'Tentar novamente';

  @override
  String get cancel => 'Cancelar';

  @override
  String get save => 'Salvar';

  @override
  String get delete => 'Excluir';

  @override
  String get confirm => 'Confirmar';

  @override
  String get close => 'Fechar';

  @override
  String get done => 'Concluído';

  @override
  String get next => 'Próximo';

  @override
  String get back => 'Voltar';

  @override
  String get loading => 'Carregando...';

  @override
  String get loadingContent => 'Carregando conteúdo';

  @override
  String get search => 'Buscar';

  @override
  String get share => 'Compartilhar';

  @override
  String get copy => 'Copiar';

  @override
  String get copied => 'Copiado!';

  @override
  String get edit => 'Editar';

  @override
  String get add => 'Adicionar';

  @override
  String get remove => 'Remover';

  @override
  String get refresh => 'Atualizar';

  @override
  String get seeAll => 'Ver tudo';

  @override
  String get seeMore => 'Ver mais';

  @override
  String get darkMode => 'Modo escuro';

  @override
  String get lightMode => 'Modo claro';

  @override
  String get systemMode => 'Seguir sistema';

  @override
  String get theme => 'Tema';

  @override
  String get audioCoach => 'Treinador de áudio';

  @override
  String get notifications => 'Notificações';

  @override
  String get privacy => 'Privacidade';

  @override
  String get account => 'Conta';

  @override
  String get about => 'Sobre';

  @override
  String get version => 'Versão';

  @override
  String get logout => 'Sair';

  @override
  String get logoutConfirm => 'Tem certeza que deseja sair?';

  @override
  String get login => 'Entrar';

  @override
  String get signUp => 'Criar conta';

  @override
  String get continueWithGoogle => 'Continuar com Google';

  @override
  String get continueWithApple => 'Continuar com Apple';

  @override
  String get welcomeBack => 'Bem-vindo de volta!';

  @override
  String get verified => 'Verificado';

  @override
  String get unverified => 'Não verificado';

  @override
  String get pending => 'Pendente';

  @override
  String get approved => 'Aprovado';

  @override
  String get rejected => 'Rejeitado';

  @override
  String get suspended => 'Suspenso';

  @override
  String get personalRecord => 'Recorde pessoal';

  @override
  String get newRecord => 'Novo recorde!';

  @override
  String get bestPace => 'Melhor pace';

  @override
  String get longestRun => 'Maior distância';

  @override
  String get totalSessions => 'Total de sessões';

  @override
  String get totalDistance => 'Distância total';

  @override
  String get recoverSession => 'Recuperar sessão';

  @override
  String get recoverSessionDescription =>
      'Uma sessão anterior não foi finalizada. Deseja recuperá-la?';

  @override
  String get resumeSession => 'Retomar';

  @override
  String get discardSession => 'Descartar';

  @override
  String distanceFormatKm(String distance) {
    return '$distance km';
  }

  @override
  String paceFormat(String pace) {
    return '$pace min/km';
  }

  @override
  String levelFormat(int level) {
    return 'Nível $level';
  }

  @override
  String coinsFormat(int count) {
    return '$count moedas';
  }

  @override
  String sessionCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sessões',
      one: '1 sessão',
      zero: 'Nenhuma sessão',
    );
    return '$_temp0';
  }

  @override
  String get myAssessoria => 'Minha Assessoria';

  @override
  String get switchAssessoria => 'Trocar de Assessoria';

  @override
  String get assessoriaFeed => 'Feed da Assessoria';

  @override
  String get consistency => 'Consistência';

  @override
  String get myEvolution => 'Minha Evolução';

  @override
  String get myRunnerDna => 'Meu DNA de Corredor';

  @override
  String get assessoriaLeague => 'Liga de Assessorias';

  @override
  String get newTicket => 'Novo chamado';

  @override
  String get runDetails => 'Detalhes da corrida';

  @override
  String get inviteFriends => 'Convidar amigos';

  @override
  String get myFriends => 'Meus Amigos';

  @override
  String get wrapped => 'Retrospectiva';
}
