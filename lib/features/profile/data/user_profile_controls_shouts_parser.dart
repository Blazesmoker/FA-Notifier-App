import 'dart:math';

import 'package:html/parser.dart' as html_parser;

import 'package:FANotifier/features/profile/domain/user_profile_api_models.dart';

ControlsShoutsPageInfo parseUserProfileControlsShoutsPage({
  required String htmlBody,
  required int pageNumber,
}) {
  final document = html_parser.parse(htmlBody);
  final entries = <ControlsShoutEntry>[];
  final shoutContainers = document.querySelectorAll(
    'form#shouts-form #shouts-list div.comment_container',
  );
  for (final container in shoutContainers) {
    final checkbox = container.querySelector(
      'input[type="checkbox"][name="shouts[]"]',
    );
    final shoutId = _normalizeShoutIdValue(checkbox?.attributes['value']);
    if (shoutId.isEmpty) {
      continue;
    }

    final avatarElement =
        container.querySelector('img.comment_useravatar');
    final avatarUrl = _normalizeComparableUrl(
      avatarElement?.attributes['src'] ?? '',
    );
    final profileLink = container.querySelector(
      '.avatar a[href*="/user/"], '
      'a.c-usernameBlock__userName[href*="/user/"], '
      'a.c-usernameBlock__displayName[href*="/user/"]',
    );
    final profileNickname = _extractProfileNickname(
      profileLink?.attributes['href'],
    );
    final dateElement = container.querySelector('span.popup_date');
    final popupDateFull = _normalizeComparableValue(
      dateElement?.attributes['title'] ?? dateElement?.text ?? '',
    );
    final messageElement =
        container.querySelector('comment-user-text.comment_text');
    final messageHtml = messageElement?.innerHtml.trim() ?? '';

    entries.add(
      ControlsShoutEntry(
        id: shoutId,
        page: pageNumber,
        avatarUrl: avatarUrl,
        profileNickname: profileNickname,
        popupDateFull: popupDateFull,
        messageHtml: messageHtml,
      ),
    );
  }

  final ids = entries.map((entry) => entry.id).toSet();
  final options = document.querySelectorAll(
    'form.c-shoutPaginationForm select[name="page"] option',
  );
  final pageValues = options
      .map((option) => int.tryParse(option.attributes['value'] ?? ''))
      .whereType<int>()
      .toSet();
  final totalPages = pageValues.isEmpty ? 1 : pageValues.reduce(max);
  return ControlsShoutsPageInfo(
    page: pageNumber,
    totalPages: totalPages,
    shoutIds: ids,
    entries: entries,
  );
}

String _normalizeShoutIdValue(dynamic rawValue) {
  if (rawValue == null) {
    return '';
  }
  final value = rawValue.toString().trim();
  if (value.isEmpty) {
    return '';
  }
  if (RegExp(r'^\d+$').hasMatch(value)) {
    return value;
  }
  final anchorMatch = RegExp(r'shout-(\d+)').firstMatch(value);
  if (anchorMatch != null) {
    return anchorMatch.group(1) ?? '';
  }
  return '';
}

String _normalizeComparableValue(String value) {
  return value.replaceAll(RegExp(r'\s+'), ' ').trim();
}

String _normalizeComparableUrl(String url) {
  final trimmed = url.trim();
  if (trimmed.isEmpty) {
    return '';
  }
  if (trimmed.startsWith('//')) {
    return 'https:$trimmed';
  }
  if (trimmed.startsWith('/')) {
    return 'https://www.furaffinity.net$trimmed';
  }
  return trimmed;
}

String _extractProfileNickname(String? href) {
  if (href == null || href.isEmpty) {
    return '';
  }
  final parts = href.split('/').where((part) => part.isNotEmpty).toList();
  final userIndex = parts.indexOf('user');
  if (userIndex != -1 && userIndex + 1 < parts.length) {
    return parts[userIndex + 1].toLowerCase();
  }
  return parts.isEmpty ? '' : parts.last.toLowerCase();
}
