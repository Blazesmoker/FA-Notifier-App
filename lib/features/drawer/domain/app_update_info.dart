class AppUpdateInfo {
  const AppUpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.updateAvailable,
    required this.currentVersionAllowed,
  });

  final String currentVersion;
  final String latestVersion;
  final bool updateAvailable;
  final bool currentVersionAllowed;
}
