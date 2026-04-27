class UserLink {
  final String rawUsername;
  final String url;

  UserLink({required this.rawUsername, required this.url});

  String get cleanUsername => rawUsername.trim();

  String get nickname {
    final uri = Uri.parse(url);
    if (uri.pathSegments.length >= 2 && uri.pathSegments[0] == 'user') {
      return uri.pathSegments[1];
    }
    return cleanUsername;
  }
}
