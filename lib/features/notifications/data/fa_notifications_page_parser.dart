import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:fanotifier/features/ads/data/fa_ad_parser.dart';

import 'package:fanotifier/features/notifications/data/fa_notification_link_parser.dart';
import 'package:fanotifier/features/notifications/data/notification_section_parser_helpers.dart';
import 'package:fanotifier/features/notifications/data/notification_shout_parser.dart';
import 'package:fanotifier/features/notifications/domain/fa_notification_models.dart';
import 'package:fanotifier/features/notifications/domain/fa_notifications_page_parser_state.dart';
import 'package:fanotifier/features/notifications/domain/fa_notifications_page_snapshot.dart';
import 'package:fanotifier/features/notifications/domain/notification_shout_mapper.dart';
import 'package:fanotifier/shared/fa/domain/notification_counts.dart';
import 'package:fanotifier/shared/fa/domain/notifications.dart';

FaNotificationsPageSnapshot parseFaNotificationsPage(
  String htmlBody, {
  required Map<String, int> messageBarCounts,
  required FaNotificationsPageParserState sideState,
  int? startedAtMilliseconds,
  Uri? documentUri,
  bool? sfwEnabled,
}) {
  final document = html_parser.parse(htmlBody);

  final messageBar = document.querySelector('li.message-bar-desktop') ??
      document.querySelector('li.noblock');
  if (messageBar == null) {
    throw Exception('Notification counters not found.');
  }
  messageBarCounts.clear();
  final links = messageBar.querySelectorAll('a.notification-container');
  bool foundNotificationCounter = false;
  for (final link in links) {
    final href = link.attributes['href'] ?? '';
    final text = link.text.trim();
    final title = (link.attributes['title'] ?? '').trim();
    final typeKey =
        notificationTypeKeyFromHrefOrTitle(href: href, title: title);
    if (typeKey == null) continue;
    foundNotificationCounter = true;
    final int count = extractNotificationCount(
      title.isNotEmpty ? title : text,
    );
    if (count > 0) {
      messageBarCounts[typeKey] = count;
    }
  }
  if (!foundNotificationCounter) {
    throw Exception('Notification counters not found.');
  }

  final body = document.querySelector('body');
  final bool isClassic =
      body?.attributes['data-static-path'] == '/themes/classic';
  int registeredUsersOnline = 0;
  if (isClassic) {
    final center = document.querySelector('div.footer center');
    final onlineStatsText = center?.text ?? '';
    final registeredUsersMatch = RegExp(
      r'(\d+)\s+registered',
      caseSensitive: false,
    ).firstMatch(onlineStatsText);
    if (registeredUsersMatch != null) {
      registeredUsersOnline =
          int.tryParse(registeredUsersMatch.group(1)!.replaceAll(',', '')) ?? 0;
    }
  } else {
    final statsDiv = document.querySelector('div.online-stats');
    final onlineStatsText = statsDiv?.text ?? '';
    final registeredUsersMatch = RegExp(
      r'(\d+)\s+registered',
      caseSensitive: false,
    ).firstMatch(onlineStatsText);
    if (registeredUsersMatch != null) {
      registeredUsersOnline =
          int.tryParse(registeredUsersMatch.group(1)!.replaceAll(',', '')) ?? 0;
    }
  }

  final int s = messageBarCounts['S'] ?? 0;
  final int w = messageBarCounts['W'] ?? 0;
  final int c = messageBarCounts['C'] ?? 0;
  final int f = messageBarCounts['F'] ?? 0;
  final int j = messageBarCounts['J'] ?? 0;
  final int n = messageBarCounts['N'] ?? 0;
  sideState.latestCounts = NotificationCounts(
    submissions: s,
    watches: w,
    comments: c,
    favorites: f,
    journals: j,
    notes: n,
  );
  sideState.hasValidLatestCountsSnapshot = true;
  sideState.latestTopBarNotifications = Notifications(
    submissions: '$s',
    watches: '$w',
    journals: '$j',
    notes: '$n',
    comments: '$c',
    favorites: '$f',
    registeredUsersOnline: '$registeredUsersOnline',
  );

  sideState.currentUsername = extractNotificationMenubarUsername(document);
  sideState.hasParsedCurrentUsername = true;

  List<dom.Element> containers =
      document.querySelectorAll('section.section_container');
  if (containers.isEmpty) {
    containers = document.querySelectorAll('fieldset');
  }

  final formAction =
      document.querySelector('form#messages-form')?.attributes['action'] ??
          '/msg/others/';

  final fetchedSections = <NotificationSection>[];
  for (var container in containers) {
    String heading = notificationSectionHeadingFromContainer(container);

    if (heading.toLowerCase().contains('shouts')) {
      final shouts = deduplicateNotificationShouts(
        mergeMessageCenterShoutsWithProfile(
          messageItems: parseMessageCenterShouts(document)
              .where((item) => (item['id'] as String? ?? '').trim().isNotEmpty)
              .toList(),
          profileShouts: const [],
        ),
      );
      fetchedSections.add(
        NotificationSection(
          title: heading,
          formAction: formAction,
          items: shouts
              .map((shout) => NotificationItem(
                    id: shout.id,
                    content: shout.textContent,
                    username: shout.nickname,
                    linkUsername: shout.nicknameLink,
                    avatarUrl: shout.avatarUrl,
                    date: shout.postedAgo,
                    fullDate: shout.postedTitle,
                  ))
              .toList(),
        ),
      );
      continue;
    }

    final liItems = container
        .querySelectorAll('ul.message-stream > li')
        .where((li) => !li.classes.contains('section-controls'))
        .toList();

    final items = <NotificationItem>[];
    for (var li in liItems) {
      dom.Element? checkbox = li.querySelector('input[type="checkbox"]');
      String id = checkbox?.attributes['value'] ?? '';

      String date = '';
      String fullDate = '';
      dom.Element? dateElm = li.querySelector('.popup_date');
      if (dateElm != null) {
        date = dateElm.text.trim();
        fullDate = dateElm.attributes['title'] ?? date;
        dateElm.remove();
      }

      String content = li.innerHtml
          .trim()
          .replaceAll(RegExp(r'<input[^>]*>'), '')
          .trim();

      String? username;
      String? submissionId;
      String? journalId;
      String? url;
      String? avatarUrl;
      final lowerHeading = heading.toLowerCase();

      if (lowerHeading.contains('watches')) {
        bool isClassic = document
                .querySelector('body')
                ?.attributes['data-static-path'] ==
            '/themes/classic';
        if (isClassic) {
          dom.Element? tableElem = li.querySelector('table');
          if (tableElem != null) {
            dom.Element? av =
                tableElem.querySelector('td.avatar a img.avatar');

            dom.Element? avatarLink = li.querySelector('td.avatar a');
            if (avatarLink != null) {
              sideState.linkUsername = extractNotificationUsernameFromHref(
                avatarLink.attributes['href'],
              );
            }
            if (av != null) {
              avatarUrl = normalizeNotificationImageUrl(
                av.attributes['src'],
              );
            }
          }
          dom.Element? infoDiv = li.querySelector('div.info');
          if (infoDiv != null) {
            sideState.displayName = infoDiv.querySelector('span')?.text.trim();
          }

          dom.Element? avatarLink = li.querySelector('td.avatar a');
          if (avatarLink != null) {
            username = extractNotificationUsernameFromHref(
              avatarLink.attributes['href'],
            );
          }

          String avatarHtml = li.querySelector('div.avatar')?.outerHtml ?? '';
          String infoHtml = li.querySelector('div.info')?.outerHtml ?? '';
          content = avatarHtml + infoHtml;
        } else {
          dom.Element? infoDiv = li.querySelector('div.info');
          if (infoDiv != null) {
            dom.Element? avatarLink = li.querySelector('div.avatar a');
            if (avatarLink != null) {
              sideState.linkUsername = extractNotificationUsernameFromHref(
                avatarLink.attributes['href'],
              );
            }
            sideState.displayName = infoDiv.querySelector('span')?.text.trim();
            dom.Element? avatarImg =
                li.querySelector('div.avatar img.avatar');
            if (avatarImg != null) {
              avatarUrl = normalizeNotificationImageUrl(
                avatarImg.attributes['src'],
              );
            }
            content = infoDiv.outerHtml;
          }
        }
      } else if (lowerHeading.contains('favorites')) {
        dom.Element? subLink = li.querySelector('a[href*="/view/"]');
        if (subLink != null) {
          url = subLink.attributes['href'];
          submissionId = extractNotificationSubmissionIdFromHref(url);
          content = content.replaceAll('"', '');
        }
      } else if (lowerHeading.contains('journal comments')) {
        dom.Element? journLink = li.querySelector('a[href*="/journal/"]');
        if (journLink != null) {
          url = journLink.attributes['href'];
          journalId = extractNotificationJournalIdFromHref(url);
        }
        content = content
            .replaceFirst(
              RegExp(r'\s*has replied to your journal titled\s*'),
              ' replied to your journal ',
            )
            .replaceAll('"', '');
        if (content.isNotEmpty) {
          content = content.substring(0, content.length - 1);
        }
      } else if (lowerHeading.contains('submission comments')) {
        dom.Element? subLink = li.querySelector('a[href*="/view/"]');
        if (subLink != null) {
          url = subLink.attributes['href'];
          submissionId = extractNotificationSubmissionIdFromHref(url);
          content = content.replaceAll('"', '');
        }
        if (content.isNotEmpty) {
          content = content.substring(0, content.length - 1);
        }
      } else if (lowerHeading.contains('journals')) {
        dom.Element? journLink = li.querySelector('a[href*="/journal/"]');
        if (journLink != null) {
          url = journLink.attributes['href'];
          journalId = extractNotificationJournalIdFromHref(url);
        }
        content = content.trim();
        content = content.replaceAll('"', '').trim();
        content =
            content.replaceFirst(RegExp(r',\s*posted by'), ' posted by');
        if (content.endsWith(',')) {
          content = content.substring(0, content.length - 1).trim();
        }
      }

      items.add(
        NotificationItem(
          id: id,
          content: content,
          username: username,
          linkUsername: sideState.linkUsername,
          submissionId: submissionId,
          journalId: journalId,
          url: url,
          avatarUrl: avatarUrl,
          date: date,
          fullDate: fullDate,
        ),
      );
    }

    fetchedSections.add(
      NotificationSection(
        title: heading,
        formAction: formAction,
        items: items,
      ),
    );
  }

  return FaNotificationsPageSnapshot(
    startedAtMilliseconds: startedAtMilliseconds,
    documentSfwEnabled: sfwEnabled,
    ads: documentUri == null || sfwEnabled == null
        ? null
        : parseFaAdPage(
            html: htmlBody,
            parsedDocument: document,
            documentUri: documentUri,
            sfwEnabled: sfwEnabled,
          ),
    messageBarCounts: messageBarCounts,
    latestCounts: sideState.latestCounts!,
    latestTopBarNotifications: sideState.latestTopBarNotifications!,
    currentUsername: sideState.currentUsername!,
    sections: fetchedSections,
    linkUsername: sideState.linkUsername,
    displayName: sideState.displayName,
  );
}
