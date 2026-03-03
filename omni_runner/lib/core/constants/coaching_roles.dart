/// Canonical coaching role constants — single source of truth.
///
/// DB values are lowercase ASCII, no accents.
/// Every role check in the app must use [CoachingRole] or these constants.
library;

/// Database string for admin_master role.
const String kRoleAdminMaster = 'admin_master';

/// Database string for coach (trainer/professor) role.
const String kRoleCoach = 'coach';

/// Database string for assistant role.
const String kRoleAssistant = 'assistant';

/// Database string for athlete role.
const String kRoleAthlete = 'athlete';

/// All staff roles (can operate the coaching ecosystem).
const List<String> kStaffRoles = [kRoleAdminMaster, kRoleCoach, kRoleAssistant];

/// Manager roles (can manage members, events, settings).
const List<String> kManagerRoles = [kRoleAdminMaster, kRoleCoach];
