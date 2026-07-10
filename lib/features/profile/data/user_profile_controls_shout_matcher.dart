import 'package:html/parser.dart' as html_parser;

import 'package:FANotifier/features/profile/domain/shout.dart';
import 'package:FANotifier/features/profile/domain/user_profile_api_models.dart';

ControlsShoutEntry? findMatchingUserProfileControlsShout({
  required List<ControlsShoutEntry> entries,
  required Shout shout,
  required Set<String> usedIds,
}) {
  for (final entry in entries) {
    if (usedIds.contains(entry.id)) {
      continue;
    }
    if (_controlsEntryMatchesShout(entry, shout)) {
      return entry;
    }
  }
  return null;
}

bool _controlsEntryMatchesShout(
  ControlsShoutEntry entry,
  Shout shout,
) {
  if (shout.id.isNotEmpty && shout.id == entry.id) {
    return true;
  }

  final shoutNickname = _normalizeComparableNickname(shout.profileNickname);
  final entryNickname = _normalizeComparableNickname(entry.profileNickname);
  if (shoutNickname.isNotEmpty &&
      entryNickname.isNotEmpty &&
      shoutNickname != entryNickname) {
    return false;
  }

  final shoutDate = _normalizeComparableValue(shout.popupDateFull);
  final entryDate = _normalizeComparableValue(entry.popupDateFull);
  if (shoutDate.isNotEmpty &&
      entryDate.isNotEmpty &&
      shoutDate != entryDate) {
    return false;
  }

  final shoutHtml = _normalizeComparableMessageHtml(shout.text);
  final entryHtml = _normalizeComparableMessageHtml(entry.messageHtml);
  if (shoutHtml.isNotEmpty && entryHtml.isNotEmpty && shoutHtml == entryHtml) {
    return true;
  }

  final shoutText = _normalizeComparableMessageText(shout.text);
  final entryText = _normalizeComparableMessageText(entry.messageHtml);
  if (shoutText.isNotEmpty && entryText.isNotEmpty && shoutText == entryText) {
    return true;
  }

  final shoutAvatar = _normalizeComparableUrl(shout.avatarUrl);
  final entryAvatar = _normalizeComparableUrl(entry.avatarUrl);
  return shoutDate.isNotEmpty &&
      entryDate.isNotEmpty &&
      shoutDate == entryDate &&
      shoutNickname.isNotEmpty &&
      entryNickname.isNotEmpty &&
      shoutNickname == entryNickname &&
      (shoutAvatar.isEmpty ||
          entryAvatar.isEmpty ||
          shoutAvatar == entryAvatar);
}

String _normalizeComparableMessageHtml(String rawHtml) {
  if (rawHtml.trim().isEmpty) {
    return '';
  }
  final document = html_parser.parse('<div id="root">$rawHtml</div>');
  final root = document.querySelector('#root');
  if (root == null) {
    return '';
  }
  final content = root.querySelector('.user-submitted-links') ?? root;
  return _normalizeComparableValue(content.innerHtml);
}

String _normalizeComparableMessageText(String rawHtml) {
  if (rawHtml.trim().isEmpty) {
    return '';
  }
  final document = html_parser.parse('<div id="root">$rawHtml</div>');
  final root = document.querySelector('#root');
  if (root == null) {
    return '';
  }
  final content = root.querySelector('.user-submitted-links') ?? root;
  return _normalizeComparableValue(content.text);
}

String _normalizeComparableNickname(String value) {
  return _normalizeComparableValue(value).toLowerCase();
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
