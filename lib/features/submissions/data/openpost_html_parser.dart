import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import 'package:fanotifier/features/submissions/domain/openpost_models.dart';
import 'package:fanotifier/shared/fa/parsing_utils.dart';

String decodeOpenPostResponseBody(List<int> bodyBytes) {
  try {
    return utf8.decode(bodyBytes);
  } on FormatException {
    try {
      return utf8.decode(bodyBytes, allowMalformed: true);
    } catch (_) {
      return latin1.decode(bodyBytes, allowInvalid: true);
    }
  }
}

String decodeOpenPostFavoriteLinksBody(String body, List<int> bodyBytes) {
  try {
    return body;
  } on FormatException {
    return utf8.decode(bodyBytes, allowMalformed: true);
  }
}

Future<dom.Document> parseOpenPostHtmlDocument(String htmlBody) {
  return compute(parseHtml, htmlBody);
}

bool hasSubmissionNotFoundError(String htmlBody) {
  final document = html_parser.parse(htmlBody);
  final allSections = document.querySelectorAll('section');
  for (final section in allSections) {
    final header =
        section.querySelector('.section-header h2') ?? section.querySelector('h2');
    final body = section.querySelector('.section-body');

    if (header != null && body != null) {
      final headerText = header.text.toLowerCase().trim();
      final bodyText = body.text.toLowerCase().trim();

      if (headerText.contains('system error') &&
          bodyText.contains('not in our database')) {
        return true;
      }
    }
  }
  return false;
}

bool hasMatureContentWarning(String htmlBody) {
  final document = html_parser.parse(htmlBody);
  final noticeSection = document.querySelector('section.notice-message');
  if (noticeSection == null) return false;

  final noticeText = noticeSection.text.toLowerCase().trim();
  return (noticeText.contains('mature') || noticeText.contains('adult')) &&
      (noticeText.contains('rated') || noticeText.contains('content')) &&
      (noticeText.contains('account settings') ||
          noticeText.contains('log in') ||
          noticeText.contains('enable'));
}

bool hasOldMatureImageError(String htmlBody) {
  final document = html_parser.parse(htmlBody);
  final body = document.querySelector('body');
  return body?.attributes['id'] == 'pageid-matureimage-error';
}

bool hasMatureRatingNotice(dom.Document document) {
  final noticeSection = document.querySelector('section.notice-message');
  if (noticeSection == null) return false;

  final noticeText = noticeSection.text.toLowerCase().trim();
  return (noticeText.contains('mature') || noticeText.contains('adult')) &&
      (noticeText.contains('rated') || noticeText.contains('content'));
}

OpenPostUserPageActions parseOpenPostUserPageActions(dom.Document document) {
  final isClassic = document
          .querySelector('body')
          ?.attributes['data-static-path']
          ?.contains('themes/classic') ??
      false;

  String? watchLink;
  String? unwatchLink;
  String? blockLink;
  String? unblockLink;
  String? blockKey;
  String? unblockKey;

  if (!isClassic) {
    watchLink = _href(
          document,
          'a.button.standard.go[href^="/watch/"]',
        ) ??
        _href(document, 'a.cat[href^="/watch/"]');
    unwatchLink = _href(
          document,
          'a.button.standard.stop[href^="/unwatch/"]',
        ) ??
        _href(document, 'a.cat[href^="/unwatch/"]');
    blockLink = _href(
          document,
          'a.button.standard.stop[href^="/block/"]',
        ) ??
        _href(document, 'a.cat[href^="/block/"]');
    unblockLink = _href(
          document,
          'a.button.standard.stop[href^="/unblock/"]',
        ) ??
        _href(document, 'a.cat[href^="/unblock/"]');
  } else {
    watchLink = _href(document, 'b > a[href^="/watch/"]');
    unwatchLink = _href(document, 'b > a[href^="/unwatch/"]');

    final blockForm = document.querySelector('form[action^="/block/"]');
    if (blockForm != null) {
      final blockButton = blockForm.querySelector('button');
      if (blockButton != null && blockButton.text.trim().contains('+Block')) {
        blockLink = blockForm.attributes['action'];
        blockKey = blockButton.attributes['value'];
      }
    }

    final unblockForm = document.querySelector('form[action^="/unblock/"]');
    if (unblockForm != null) {
      final unblockButton = unblockForm.querySelector('button');
      if (unblockButton != null &&
          unblockButton.text.trim().contains('-Unblock')) {
        unblockLink = unblockForm.attributes['action'];
        unblockKey = unblockButton.attributes['value'];
      }
    }
  }

  return OpenPostUserPageActions(
    isClassic: isClassic,
    watchLink: watchLink,
    unwatchLink: unwatchLink,
    blockLink: blockLink,
    unblockLink: unblockLink,
    blockKey: blockKey,
    unblockKey: unblockKey,
  );
}

String? _href(dom.Document document, String selector) {
  return document.querySelector(selector)?.attributes['href'];
}
