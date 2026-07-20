import 'dart:convert';

import 'package:html/parser.dart' as html_parser;

import 'package:fanotifier/features/profile/domain/shout.dart';

List<Shout> parseAdditionalProfileShoutsJson(
  String jsonBody,
  Set<String> existingShoutIds,
  int sourcePage,
) {
  final newShouts = <Shout>[];
  try {
    final jsonData = json.decode(jsonBody) as Map<String, dynamic>;
    if (!jsonData.containsKey('shouts')) return newShouts;

    final shoutsList = jsonData['shouts'] as List<dynamic>;
    for (final shoutData in shoutsList) {
      if (shoutData is! Map) {
        continue;
      }

      final shoutMap = Map<String, dynamic>.from(shoutData);
      final shoutId = _extractShoutIdFromPayload(shoutMap);
      if (shoutId.isNotEmpty && existingShoutIds.contains(shoutId)) {
        continue;
      }

      String avatarUrl = shoutMap['avatar_url'] ?? '';
      if (avatarUrl.startsWith('//')) {
        avatarUrl = 'https:$avatarUrl';
      }

      final String displayNameHtml =
          shoutMap['shout_display_name_with_icons'] ?? '';
      final displayNameDocument = html_parser.parse(displayNameHtml);
      final displayNameElement =
          displayNameDocument.querySelector('.js-displayName');
      final userNameElement = displayNameDocument
          .querySelector('a.c-usernameBlock__userName span');
      final symbolElement =
          displayNameDocument.querySelector('.c-usernameBlock__symbol');

      final displayName = displayNameElement?.text.trim() ?? 'Unknown';
      final userNamePart = userNameElement?.text.trim() ?? '';
      final symbol = symbolElement?.text.trim() ?? '~';
      final usernameWithoutSymbol = userNamePart.replaceFirst(symbol, '').trim();
      final commentUsername = usernameWithoutSymbol.isEmpty ||
              displayName.toLowerCase() == usernameWithoutSymbol.toLowerCase()
          ? displayName
          : '$displayName\n@$usernameWithoutSymbol';

      var profileNickname = 'Unknown';
      final profileLink =
          displayNameDocument.querySelector('a[href*="/user/"]');
      final profileHref = profileLink?.attributes['href'];
      if (profileHref != null) {
        profileNickname =
            profileHref.split('/').where((part) => part.isNotEmpty).last;
      }

      var relativeDate = 'Unknown date';
      var fullDate = 'Unknown date';
      final String dateHtml = shoutMap['thisdate'] ?? '';
      if (dateHtml.isNotEmpty) {
        final dateDocument = html_parser.parse(dateHtml);
        final dateElement = dateDocument.querySelector('span.popup_date');
        if (dateElement != null) {
          relativeDate = dateElement.text.trim();
          fullDate = dateElement.attributes['title']?.trim() ?? relativeDate;
        }
      }

      final String text = shoutMap['message'] ?? '';

      final iconBeforeUrls = displayNameDocument
          .querySelectorAll('usericon-block-before img')
          .map((element) {
            final src = element.attributes['src'];
            if (src != null) {
              if (src.startsWith('//')) return 'https:$src';
              if (src.startsWith('/')) {
                return 'https://www.furaffinity.net$src';
              }
              return src;
            }
            return '';
          })
          .where((src) => src.isNotEmpty)
          .toList();
      final iconAfterUrls = displayNameDocument
          .querySelectorAll('usericon-block-after img')
          .map((element) {
            final src = element.attributes['src'];
            if (src != null) {
              if (src.startsWith('//')) return 'https:$src';
              if (src.startsWith('/')) {
                return 'https://www.furaffinity.net$src';
              }
              return src;
            }
            return '';
          })
          .where((src) => src.isNotEmpty)
          .toList();

      newShouts.add(
        Shout(
          id: shoutId,
          avatarUrl: avatarUrl,
          username: commentUsername,
          profileNickname: profileNickname,
          date: relativeDate,
          text: text,
          popupDateFull: fullDate,
          popupDateRelative: relativeDate,
          iconBeforeUrls: iconBeforeUrls,
          iconAfterUrls: iconAfterUrls,
          symbol: symbol,
          sourcePage: sourcePage,
        ),
      );
    }
  } catch (_) {}

  return newShouts;
}

String _extractShoutIdFromPayload(Map<String, dynamic> shoutData) {
  const directKeys = ['anchor_id', 'anchor', 'id', 'shout_id', 'comment_id'];
  for (final key in directKeys) {
    final normalized = _normalizeShoutIdValue(shoutData[key]);
    if (normalized.isNotEmpty) {
      return normalized;
    }
  }

  for (final value in shoutData.values) {
    final normalized = _extractShoutIdFromDynamic(value);
    if (normalized.isNotEmpty) {
      return normalized;
    }
  }
  return '';
}

String _extractShoutIdFromDynamic(dynamic value) {
  final direct = _normalizeShoutIdValue(value);
  if (direct.isNotEmpty) {
    return direct;
  }

  if (value is Map) {
    for (final nestedValue in value.values) {
      final nested = _extractShoutIdFromDynamic(nestedValue);
      if (nested.isNotEmpty) {
        return nested;
      }
    }
  } else if (value is Iterable) {
    for (final nestedValue in value) {
      final nested = _extractShoutIdFromDynamic(nestedValue);
      if (nested.isNotEmpty) {
        return nested;
      }
    }
  }
  return '';
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
  return RegExp(r'shout-(\d+)').firstMatch(value)?.group(1) ?? '';
}
