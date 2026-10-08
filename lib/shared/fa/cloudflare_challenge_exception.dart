class CloudflareChallengeException implements Exception {
  final String? initialUrl;

  const CloudflareChallengeException({this.initialUrl});

  @override
  String toString() => 'Cloudflare verification is required.';
}
