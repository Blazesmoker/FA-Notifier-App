bool hasLoggedInHomeElement(String? html) {
  if (html == null) return false;

  final isClassicTheme = html.contains('data-static-path="/themes/classic"');
  final usernameElementFound = isClassicTheme &&
      RegExp(r'<(?:a|span) id="my-username"').hasMatch(html);
  final avatarElementFound =
      !isClassicTheme && html.contains('loggedin_user_avatar');

  return usernameElementFound || avatarElementFound;
}
