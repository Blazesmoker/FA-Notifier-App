class CloudflareChallengeException implements Exception {
  final String? initialUrl;

  const CloudflareChallengeException({this.initialUrl});
}
