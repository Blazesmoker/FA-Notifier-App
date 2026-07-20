import 'package:flutter/foundation.dart';
import 'package:html/dom.dart' as dom;

import 'package:fanotifier/features/notifications/data/fa_notification_link_parser.dart';
import 'package:fanotifier/features/notifications/domain/fa_notification_models.dart';

String extractNotificationMenubarUsername(dom.Document document) {
  final body = document.querySelector('body');
  final isClassic = body?.attributes['data-static-path'] == '/themes/classic';
  final myUsernameElement = document.getElementById('my-username');
  if (myUsernameElement != null) {
    final href = myUsernameElement.attributes['href'];
    if (href != null) {
      final username = extractNotificationUsernameFromHref(href);
      if (username != null) return username;
    }
  }

  if (!isClassic) {
    final menubarLink = document
        .querySelector('div.floatleft.hideonmobile a[href*="/user/"]');
    final href = menubarLink?.attributes['href'];
    if (href != null) {
      final username = extractNotificationUsernameFromHref(href);
      if (username != null) return username;
    }
  }
  return '';
}

List<Map<String, dynamic>> parseMessageCenterShouts(dom.Document document) {
  final results = <Map<String, dynamic>>[];
  final isClassic = document
          .querySelector('body')
          ?.attributes['data-static-path'] ==
      '/themes/classic';

  if (isClassic) {
    final listItems = document
        .querySelectorAll('li')
        .where(
          (element) =>
              element.querySelector(
                'input[type="checkbox"][name="shouts[]"]',
              ) !=
              null,
        )
        .toList();
    debugPrint(
      '[fetchMsgOthersShouts] Found ${listItems.length} classic shout <li> items',
    );
    for (final listItem in listItems) {
      final checkbox = listItem.querySelector(
        'input[type="checkbox"][name="shouts[]"]',
      );
      final id = checkbox?.attributes['value'] ?? '';
      final isRemoved =
          listItem.text.toLowerCase().contains('shout has been removed');
      var nickname = '';
      var nicknameLink = '';
      if (!isRemoved) {
        final nameSpan = listItem.querySelector(
          'span.c-usernameBlockSimple.username-underlined a span.c-usernameBlockSimple__displayName',
        );
        if (nameSpan != null) nickname = nameSpan.text.trim();
        nicknameLink = extractNotificationNicknameLink(listItem);
      }
      var postedAgo = '';
      var postedTitle = '';
      final timeSpan = listItem.querySelector('span.popup_date');
      if (timeSpan != null) {
        postedAgo = timeSpan.text.trim();
        postedTitle = (timeSpan.attributes['title'] ?? postedAgo)
            .replaceFirst(RegExp(r'^on\s+'), '')
            .trim();
      }
      results.add({
        'id': id,
        'nickname': nickname,
        'nicknameLink': nicknameLink,
        'postedTitle': postedTitle,
        'postedAgo': postedAgo,
        'isRemoved': isRemoved,
      });
    }

    final tableShouts = document.querySelectorAll('table[id^="shout-"]');
    debugPrint(
      '[fetchMsgOthersShouts] Found ${tableShouts.length} classic shout <table> items',
    );
    for (final table in tableShouts) {
      final shoutId = table.id.replaceFirst('shout-', '');
      final isRemoved =
          table.text.toLowerCase().contains('shout has been removed');
      var nickname = '';
      var nicknameLink = '';
      final nameElement = table.querySelector(
        'div.c-usernameBlock a.c-usernameBlock__displayName',
      );
      if (nameElement != null) {
        nickname = nameElement.text.trim();
        final href = nameElement.attributes['href'];
        if (href != null) {
          final match = RegExp(r'^/user/([^/]+)/?$').firstMatch(href);
          if (match != null) nicknameLink = match.group(1)!;
        }
      }

      var postedAgo = '';
      var postedTitle = '';
      final dateElement = table.querySelector('span.popup_date');
      if (dateElement != null) {
        postedAgo = dateElement.text.trim();
        postedTitle = (dateElement.attributes['title'] ?? postedAgo)
            .replaceFirst(RegExp(r'^on\s+'), '')
            .trim();
      }

      var textHtml = '';
      final content = table.querySelector('td.alt1.addpad div.no_overflow');
      if (content != null) {
        textHtml = content.innerHtml.trim();
        textHtml = textHtml.replaceAllMapped(
          RegExp(r'<i\s+class="smilie\s+([\w-]+)"[^>]*></i>'),
          (match) => '[smilie-${match.group(1)}]',
        );
      }

      var avatarUrl = '';
      final avatarImage = table.querySelector('td.alt1 a img.avatar');
      if (avatarImage != null) {
        avatarUrl = avatarImage.attributes['src'] ?? '';
        if (avatarUrl.startsWith('//')) avatarUrl = 'https:$avatarUrl';
      }

      results.add({
        'id': shoutId,
        'nickname': nickname,
        'nicknameLink': nicknameLink,
        'postedTitle': postedTitle,
        'postedAgo': postedAgo,
        'isRemoved': isRemoved,
        'avatarUrl': avatarUrl,
        'textHtml': textHtml,
      });
    }
  } else {
    final shoutSection = document.querySelector('section#messages-shouts');
    if (shoutSection == null) {
      debugPrint('[fetchMsgOthersShouts] No #messages-shouts section found.');
      return results;
    }
    final stream = shoutSection.querySelector('ul.message-stream');
    if (stream == null) {
      debugPrint(
        '[fetchMsgOthersShouts] No .message-stream found in #messages-shouts',
      );
      return results;
    }
    final listItems = stream.querySelectorAll('li');
    debugPrint('[fetchMsgOthersShouts] Found ${listItems.length} <li> items');
    for (final listItem in listItems) {
      final checkbox = listItem.querySelector(
        'input[type="checkbox"][name="shouts[]"]',
      );
      final id = checkbox?.attributes['value'] ?? '';
      final isRemoved =
          listItem.text.toLowerCase().contains('shout has been removed');
      var nickname = '';
      var nicknameLink = '';
      if (!isRemoved) {
        final nameSpan = listItem.querySelector(
          'span.c-usernameBlockSimple.username-underlined a[href*="/user/"] span.c-usernameBlockSimple__displayName',
        );
        if (nameSpan != null) nickname = nameSpan.text.trim();
        nicknameLink = extractNotificationNicknameLink(listItem);
      }
      var postedAgo = '';
      var postedTitle = '';
      final timeSpan = listItem.querySelector('div.floatright span.popup_date');
      if (timeSpan != null) {
        postedAgo = timeSpan.text.trim();
        postedTitle = (timeSpan.attributes['title'] ?? postedAgo)
            .replaceFirst(RegExp(r'^on\s+'), '')
            .trim();
      }
      results.add({
        'id': id,
        'nickname': nickname,
        'nicknameLink': nicknameLink,
        'postedTitle': postedTitle,
        'postedAgo': postedAgo,
        'isRemoved': isRemoved,
      });
    }
  }

  debugPrint('[fetchMsgOthersShouts] Returning ${results.length} items');
  return results;
}

List<Shout> mergeMessageCenterShoutsWithProfile({
  required List<Map<String, dynamic>> messageItems,
  required List<Shout> profileShouts,
}) {
  final results = <Shout>[];
  for (final message in messageItems) {
    final id = (message['id'] as String? ?? '').trim();
    final isRemoved = message['isRemoved'] as bool? ?? false;
    final postedTitle = (message['postedTitle'] as String? ?? '').trim();
    final postedAgo = (message['postedAgo'] as String? ?? '').trim();
    final nickname = (message['nickname'] as String? ?? '').trim();
    final nicknameLink = (message['nicknameLink'] as String? ?? '').trim();

    if (isRemoved) {
      results.add(
        Shout(
          id: id,
          nickname: nickname,
          nicknameLink: nicknameLink,
          postedTitle: postedTitle,
          avatarUrl: '',
          postedAgo: postedAgo,
          textContent: 'Shout has been removed from your page.',
          isRemoved: true,
        ),
      );
      continue;
    }

    final messageAvatarUrl =
        (message['avatarUrl'] as String? ?? '').trim();
    final messageTextHtml = (message['textHtml'] as String? ?? '').trim();
    if (messageAvatarUrl.isNotEmpty || messageTextHtml.isNotEmpty) {
      results.add(
        Shout(
          id: id,
          nickname: nickname,
          nicknameLink: nicknameLink,
          postedTitle: postedTitle,
          avatarUrl: messageAvatarUrl,
          postedAgo: postedAgo,
          textContent:
              messageTextHtml.isNotEmpty ? messageTextHtml : 'left a shout:',
          isRemoved: false,
        ),
      );
      continue;
    }

    final matches = profileShouts.where((profileShout) {
      final nicknameMatches = profileShout.nickname.trim().toLowerCase() ==
          nickname.trim().toLowerCase();
      final timeMatches = profileShout.postedTitle == postedTitle;
      return nicknameMatches && timeMatches;
    }).toList();
    if (matches.isNotEmpty) {
      final profileShout = matches.first;
      results.add(
        Shout(
          id: id,
          nickname: nickname,
          nicknameLink: nicknameLink,
          postedTitle: postedTitle,
          avatarUrl: profileShout.avatarUrl,
          postedAgo: postedAgo,
          textContent: profileShout.textContent,
          isRemoved: false,
        ),
      );
    } else {
      results.add(
        Shout(
          id: id,
          nickname: nickname,
          nicknameLink: nicknameLink,
          postedTitle: postedTitle,
          avatarUrl: '',
          postedAgo: postedAgo,
          textContent: '',
          isRemoved: false,
        ),
      );
    }
  }
  debugPrint('[fetchMsgCenterShouts] Final results count: ${results.length}');
  return results;
}
