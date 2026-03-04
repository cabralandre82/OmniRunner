export function appDeepLink(path: string): string {
  return `omnirunner://${path}`;
}

export function notifyAthleteLink(userId: string): string {
  return appDeepLink(`athlete/${userId}`);
}
