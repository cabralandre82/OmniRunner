// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Omni Runner';

  @override
  String get dashboard => 'Home';

  @override
  String get runs => 'Runs';

  @override
  String get challenges => 'Challenges';

  @override
  String get social => 'Social';

  @override
  String get profile => 'Profile';

  @override
  String get settings => 'Settings';

  @override
  String get more => 'More';

  @override
  String get history => 'History';

  @override
  String get progression => 'Progression';

  @override
  String get wallet => 'Wallet';

  @override
  String get leaderboards => 'Leaderboards';

  @override
  String get verification => 'Verification';

  @override
  String get diagnostics => 'Diagnostics';

  @override
  String get support => 'Support';

  @override
  String get howItWorks => 'How it works';

  @override
  String get startRun => 'Start run';

  @override
  String get stopRun => 'Stop run';

  @override
  String get pauseRun => 'Pause run';

  @override
  String get resumeRun => 'Resume run';

  @override
  String get finishRun => 'Finish run';

  @override
  String get discardRun => 'Discard run';

  @override
  String get runSummary => 'Run summary';

  @override
  String get replay => 'Run replay';

  @override
  String gpsPoints(int count) {
    return '$count GPS points recorded';
  }

  @override
  String get distance => 'Distance';

  @override
  String get pace => 'Pace';

  @override
  String get avgPace => 'Avg pace';

  @override
  String get duration => 'Duration';

  @override
  String get calories => 'Calories';

  @override
  String get elevation => 'Elevation';

  @override
  String get heartRate => 'Heart Rate';

  @override
  String get avgHeartRate => 'Avg HR';

  @override
  String get maxHeartRate => 'Max HR';

  @override
  String get cadence => 'Cadence';

  @override
  String get km => 'km';

  @override
  String get minPerKm => 'min/km';

  @override
  String get bpm => 'bpm';

  @override
  String get today => 'Today';

  @override
  String get thisWeek => 'This week';

  @override
  String get thisMonth => 'This month';

  @override
  String get allTime => 'All time';

  @override
  String get daily => 'Daily';

  @override
  String get weekly => 'Weekly';

  @override
  String get monthly => 'Monthly';

  @override
  String get noRunsYet => 'No runs yet';

  @override
  String get noRunsYetDescription =>
      'Start your first run and track your progress!';

  @override
  String get noDataYet => 'No data yet';

  @override
  String get noResultsFound => 'No results found';

  @override
  String get noChallengesYet => 'No active challenges';

  @override
  String get noChallengesYetDescription =>
      'Create or accept a challenge to compete with friends.';

  @override
  String get challengeDetails => 'Challenge details';

  @override
  String get createChallenge => 'Create challenge';

  @override
  String get joinChallenge => 'Join challenge';

  @override
  String get challengeActive => 'Active';

  @override
  String get challengeCompleted => 'Completed';

  @override
  String get challengePending => 'Pending';

  @override
  String get challengeCancelled => 'Cancelled';

  @override
  String get challengeExpired => 'Expired';

  @override
  String get groups => 'Groups';

  @override
  String get events => 'Events';

  @override
  String get friends => 'Friends';

  @override
  String get members => 'Members';

  @override
  String get rankings => 'Rankings';

  @override
  String get createGroup => 'Create group';

  @override
  String get joinGroup => 'Join group';

  @override
  String get leaveGroup => 'Leave group';

  @override
  String get groupDetails => 'Group details';

  @override
  String get inviteCode => 'Invite code';

  @override
  String get coins => 'Coins';

  @override
  String get xp => 'XP';

  @override
  String get level => 'Level';

  @override
  String get badges => 'Badges';

  @override
  String get missions => 'Missions';

  @override
  String get streak => 'Streak';

  @override
  String streakDays(int count) {
    return '$count days';
  }

  @override
  String get coaching => 'Coaching';

  @override
  String get myCoach => 'My coach';

  @override
  String get switchCoach => 'Switch coach';

  @override
  String get joinCoach => 'Join a coach';

  @override
  String get coachInsights => 'Insights';

  @override
  String get athleteEvolution => 'Athlete evolution';

  @override
  String get groupEvolution => 'Group evolution';

  @override
  String get errorGeneric => 'Something went wrong. Please try again.';

  @override
  String get errorNoConnection => 'No internet connection.';

  @override
  String get errorNoConnectionDetailed =>
      'No internet connection. Some features may not work.';

  @override
  String get errorSessionExpired =>
      'Your session has expired. Please log in again.';

  @override
  String get errorForbidden => 'You don\'t have permission for this action.';

  @override
  String get errorNotFound => 'Content not found.';

  @override
  String get errorServer => 'Server error. Please try again in a few minutes.';

  @override
  String get errorTimeout => 'The request took too long. Please try again.';

  @override
  String get retry => 'Retry';

  @override
  String get cancel => 'Cancel';

  @override
  String get save => 'Save';

  @override
  String get delete => 'Delete';

  @override
  String get confirm => 'Confirm';

  @override
  String get close => 'Close';

  @override
  String get done => 'Done';

  @override
  String get next => 'Next';

  @override
  String get back => 'Back';

  @override
  String get loading => 'Loading...';

  @override
  String get loadingContent => 'Loading content';

  @override
  String get search => 'Search';

  @override
  String get share => 'Share';

  @override
  String get copy => 'Copy';

  @override
  String get copied => 'Copied!';

  @override
  String get edit => 'Edit';

  @override
  String get add => 'Add';

  @override
  String get remove => 'Remove';

  @override
  String get refresh => 'Refresh';

  @override
  String get seeAll => 'See all';

  @override
  String get seeMore => 'See more';

  @override
  String get darkMode => 'Dark mode';

  @override
  String get lightMode => 'Light mode';

  @override
  String get systemMode => 'Follow system';

  @override
  String get theme => 'Theme';

  @override
  String get audioCoach => 'Audio coach';

  @override
  String get notifications => 'Notifications';

  @override
  String get privacy => 'Privacy';

  @override
  String get account => 'Account';

  @override
  String get about => 'About';

  @override
  String get version => 'Version';

  @override
  String get logout => 'Log out';

  @override
  String get logoutConfirm => 'Are you sure you want to log out?';

  @override
  String get login => 'Log in';

  @override
  String get signUp => 'Sign up';

  @override
  String get continueWithGoogle => 'Continue with Google';

  @override
  String get continueWithApple => 'Continue with Apple';

  @override
  String get welcomeBack => 'Welcome back!';

  @override
  String get verified => 'Verified';

  @override
  String get unverified => 'Unverified';

  @override
  String get pending => 'Pending';

  @override
  String get approved => 'Approved';

  @override
  String get rejected => 'Rejected';

  @override
  String get suspended => 'Suspended';

  @override
  String get personalRecord => 'Personal record';

  @override
  String get newRecord => 'New record!';

  @override
  String get bestPace => 'Best pace';

  @override
  String get longestRun => 'Longest run';

  @override
  String get totalSessions => 'Total sessions';

  @override
  String get totalDistance => 'Total distance';

  @override
  String get recoverSession => 'Recover session';

  @override
  String get recoverSessionDescription =>
      'A previous session was not finished. Would you like to recover it?';

  @override
  String get resumeSession => 'Resume';

  @override
  String get discardSession => 'Discard';

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
    return 'Level $level';
  }

  @override
  String coinsFormat(int count) {
    return '$count coins';
  }

  @override
  String sessionCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sessions',
      one: '1 session',
      zero: 'No sessions',
    );
    return '$_temp0';
  }

  @override
  String get myAssessoria => 'My Coach';

  @override
  String get switchAssessoria => 'Switch Coach';

  @override
  String get assessoriaFeed => 'Coach Feed';

  @override
  String get consistency => 'Consistency';

  @override
  String get myEvolution => 'My Evolution';

  @override
  String get myRunnerDna => 'My Runner DNA';

  @override
  String get assessoriaLeague => 'Coach League';

  @override
  String get newTicket => 'New ticket';

  @override
  String get runDetails => 'Run details';

  @override
  String get inviteFriends => 'Invite friends';

  @override
  String get myFriends => 'My Friends';

  @override
  String get wrapped => 'Year in Review';
}
