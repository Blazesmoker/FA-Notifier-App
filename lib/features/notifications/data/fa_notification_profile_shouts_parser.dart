import 'package:flutter/foundation.dart';
import 'package:html/dom.dart' as dom;

import 'package:fanotifier/features/notifications/data/fa_notification_link_parser.dart';
import 'package:fanotifier/features/notifications/domain/fa_notification_models.dart';

void parseNotificationProfileShouts(
  dom.Document document,
  List<Shout> shouts,
) {
  final isClassic = document
          .querySelector('body')
          ?.attributes['data-static-path'] ==
      '/themes/classic';
  if (isClassic) {
    final shoutTables = document.querySelectorAll('table[id^="shout-"]');
    debugPrint(
      '[fetchProfileShouts] Found ${shoutTables.length} classic shout table(s)',
    );
    for (final table in shoutTables) {
      var nickname = '';
      var nicknameLink = '';
      var postedTitle = '';
      var postedAgo = '';
      var textContent = '';
      var avatarUrl = '';
      final avatarImage = table.querySelector('td.alt1 a img.avatar');
      if (avatarImage != null) {
        avatarUrl = avatarImage.attributes['src'] ?? '';
        if (avatarUrl.startsWith('//')) avatarUrl = 'https:$avatarUrl';
      }
      final usernameLink = table.querySelector(
        'div.c-usernameBlock a.c-usernameBlock__displayName',
      );
      if (usernameLink != null) {
        nickname = usernameLink.text.trim();
        final href = usernameLink.attributes['href'];
        if (href != null) {
          final match = RegExp(r'^/user/([^/]+)/?$').firstMatch(href);
          if (match != null) {
            nicknameLink = match.group(1)!;
          }
        }
      }
      final dateElement = table.querySelector('span.popup_date');
      if (dateElement != null) {
        postedAgo = dateElement.text.trim();
        postedTitle = dateElement.attributes['title']
                ?.replaceFirst(RegExp(r'^on\s+'), '')
                .trim() ??
            '';
      }
      final content = table.querySelector('td.alt1.addpad div.no_overflow');
      if (content != null) {
        textContent = content.innerHtml.trim();
      }
      shouts.add(
        Shout(
          id: '',
          nickname: nickname,
          nicknameLink: nicknameLink,
          postedTitle: postedTitle,
          avatarUrl: avatarUrl,
          postedAgo: postedAgo,
          textContent: textContent,
          isRemoved: false,
        ),
      );
    }
  } else {
    final containers = document.querySelectorAll('div.comment_container');
    debugPrint(
      '[fetchProfileShouts] Found ${containers.length} modern comment_container blocks',
    );
    for (final container in containers) {
      var nickname = '';
      final nicknameLink = extractNotificationNicknameLink(container);
      var postedTitle = '';
      var postedAgo = '';
      var textContent = '';
      var avatarUrl = '';
      final displayName =
          container.querySelector('.c-usernameBlock__displayName .js-displayName');
      if (displayName != null) {
        nickname = displayName.text.trim();
      }
      final date = container.querySelector('comment-date span.popup_date');
      if (date != null) {
        postedAgo = date.text.trim();
        postedTitle = date.attributes['title']
                ?.replaceFirst(RegExp(r'^on\s+'), '')
                .trim() ??
            '';
      }
      final text = container.querySelector('comment-user-text.comment_text');
      if (text != null) {
        textContent = text.text.trim();
      }
      final avatar = container.querySelector('div.avatar');
      if (avatar != null) {
        final link = avatar.querySelector('a[href*="/user/"]');
        if (link != null) {
          final image = link.querySelector('img.comment_useravatar');
          if (image != null) {
            var src = image.attributes['src'] ?? '';
            if (src.startsWith('//')) src = 'https:$src';
            avatarUrl = src;
          }
        }
      }
      shouts.add(
        Shout(
          id: '',
          nickname: nickname,
          nicknameLink: nicknameLink,
          postedTitle: postedTitle,
          avatarUrl: avatarUrl,
          postedAgo: postedAgo,
          textContent: textContent,
          isRemoved: false,
        ),
      );
    }
  }
}
