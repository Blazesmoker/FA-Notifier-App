import 'package:html/parser.dart' as html_parser;

class FaSystemMessage {
  const FaSystemMessage({
    required this.message,
    this.retryAfter,
    required this.isMaintenanceOrUnavailable,
  });

  final String message;
  final Duration? retryAfter;
  final bool isMaintenanceOrUnavailable;

  bool get isWaitingToRetry => retryAfter != null;
}

class FaMaintenanceUnavailableException implements Exception {
  const FaMaintenanceUnavailableException(this.message);

  final String message;

  @override
  String toString() => message;
}

FaSystemMessage? parseFaSystemMessage(Object? html) {
  if (html == null) return null;
  final raw = html.toString();
  if (raw.trim().isEmpty) return null;

  final document = html_parser.parse(raw);
  final redirectMessage = document.querySelector('.redirect-message');
  final noticeSection = document.querySelector('section.notice-message') ??
      document.querySelector('.notice-message');

  String? text;
  if (redirectMessage != null) {
    text = redirectMessage.text;
  } else if (noticeSection != null) {
    text = noticeSection.text;
  } else {
    final h2 = document.querySelector('#standardpage h2');
    final standardPage = document.querySelector('#standardpage');
    if (h2 != null &&
        standardPage != null &&
        h2.text.toLowerCase().contains('system message')) {
      text = standardPage.text;
    } else {
      final bodyText = document.body?.text;
      if (bodyText != null &&
          !_hasNormalFaContent(raw) &&
          isFaMaintenanceOrUnavailableText(bodyText)) {
        text = bodyText;
      }
    }
  }

  if (text == null) return null;

  final message = trimFaSystemMessageForDisplay(
    cleanFaSystemMessageText(text),
  );
  if (message.isEmpty) return null;

  return FaSystemMessage(
    message: message,
    retryAfter: parseFaRetryAfter(message),
    isMaintenanceOrUnavailable: isFaMaintenanceOrUnavailableText(message),
  );
}

bool _hasNormalFaContent(String html) {
  final lower = html.toLowerCase();
  return lower.contains('id="notes-list"') ||
      lower.contains('class="gallery"') ||
      lower.contains('class="figure"') ||
      lower.contains('<figure') ||
      lower.contains('form id="messages-form"') ||
      lower.contains('img id="submissionimg"') ||
      lower.contains('pageid-messagecenter') ||
      lower.contains('pageid-browse') ||
      lower.contains('pageid-search');
}

String cleanFaSystemMessageText(String text) {
  var cleaned = text
      .replaceAll('\u00a0', ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  cleaned = cleaned.replaceFirst(
    RegExp(r'^System Message\s*', caseSensitive: false),
    '',
  );
  cleaned = cleaned.replaceAll(
    RegExp(r'Click\s+"?Continue"?\s+to\s+retry\.?', caseSensitive: false),
    '',
  );
  cleaned = cleaned.replaceAll(
    RegExp(r'\bContinue\s*»?\s*$', caseSensitive: false),
    '',
  );
  cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();

  return cleaned;
}

String trimFaSystemMessageForDisplay(String text) {
  if (text.length <= 280) return text;
  final sentences = text.split(RegExp(r'[.!?]\s+'));
  final match = sentences.firstWhere(
    isFaMaintenanceOrUnavailableText,
    orElse: () => text.substring(0, 280),
  );
  return match.length <= 280 ? match : '${match.substring(0, 277).trim()}...';
}

Duration? parseFaRetryAfter(String text) {
  final patterns = [
    RegExp(r'(\d+)\s+second\(s\)\s+remaining', caseSensitive: false),
    RegExp(r'(\d+)\s+seconds?\s+remaining', caseSensitive: false),
    RegExp(r'try again in\s+(\d+)\s+seconds?', caseSensitive: false),
    RegExp(r'retry in\s+(\d+)\s+seconds?', caseSensitive: false),
  ];

  for (final pattern in patterns) {
    final match = pattern.firstMatch(text);
    if (match == null) continue;
    final seconds = int.tryParse(match.group(1) ?? '');
    if (seconds != null && seconds > 0) {
      return Duration(seconds: seconds);
    }
  }

  return null;
}

bool isFaMaintenanceOrUnavailableText(String text) {
  final lower = text.toLowerCase();
  if (parseFaRetryAfter(text) != null) return false;
  if (lower.contains('under maintenance')) return true;
  if (lower.contains('maintenance') &&
      (lower.contains('furaffinity') ||
          lower.contains('site') ||
          lower.contains('server') ||
          lower.contains('scheduled') ||
          lower.contains('temporarily') ||
          lower.contains('unavailable') ||
          lower.contains('down'))) {
    return true;
  }
  if (lower.contains('downtime')) return true;
  if (lower.contains('temporarily unavailable')) return true;
  if (lower.contains('currently unavailable')) return true;
  if (lower.contains('site unavailable')) return true;
  if (lower.contains('service unavailable')) return true;
  if (lower.contains('temporarily down')) return true;
  if (lower.contains('currently down')) return true;
  if (lower.contains('down for updates')) return true;
  if (lower.contains('down for site updates')) return true;
  if (lower.contains('please try again later') &&
      (lower.contains('unavailable') ||
          lower.contains('maintenance') ||
          lower.contains('downtime') ||
          lower.contains('down'))) {
    return true;
  }
  return false;
}
