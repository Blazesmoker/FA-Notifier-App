import 'package:html/parser.dart' as html_parser;

import 'package:FANotifier/shared/fa/domain/user_link.dart';

List<UserLink> parseWatchlistUsers(String html) {
  final document = html_parser.parse(html);
  final elements = document.querySelectorAll(
    '.watch-list-items a[href*="/user/"]',
  );

  final pageUsers = <UserLink>[];
  final seenUsernames = <String>{};
  for (final element in elements) {
    final href = element.attributes['href'];
    final rawUsername = element.text.trim();

    if (href == null || href.isEmpty || rawUsername.isEmpty) {
      continue;
    }

    final profileUrl =
        href.startsWith('http') ? href : 'https://www.furaffinity.net$href';
    final user = UserLink(rawUsername: rawUsername, url: profileUrl);
    final key = user.cleanUsername.toLowerCase();

    if (seenUsernames.add(key)) {
      pageUsers.add(user);
    }
  }

  return pageUsers;
}
