import 'package:html/parser.dart' as html_parser;

import 'package:fanotifier/shared/utils/notes_notifications_text_edit.dart';

String parseBackgroundNoteContent(dynamic htmlBody) {
  final document = html_parser.parse(htmlBody);
  final modernContentElement =
      document.querySelector('.section-body .user-submitted-links');
  if (modernContentElement != null) {
    modernContentElement
        .querySelectorAll('.noteWarningMessage.noteWarningMessage--scam')
        .forEach((element) => element.remove());
    modernContentElement
        .querySelectorAll('a.auto_link_shortened')
        .forEach((anchor) {
      final fullLink = anchor.attributes['title'] ?? anchor.attributes['href'];
      if (fullLink != null) {
        anchor.innerHtml = fullLink;
      }
    });
    final rawHtml = modernContentElement.innerHtml;
    final innerDocument = html_parser.parse(rawHtml);
    final updatedText = innerDocument.body?.text.trim() ?? '';
    final newestContent = extractNewestContent(updatedText);
    return newestContent.isNotEmpty ? newestContent : 'No content';
  }
  final classicContentElement = document.querySelector('td.noteContent.alt1');
  if (classicContentElement != null) {
    classicContentElement
        .querySelectorAll('.noteWarningMessage.noteWarningMessage--scam')
        .forEach((element) => element.remove());
    classicContentElement
        .querySelector('span[style*="color: #999999"]')
        ?.remove();
    classicContentElement
        .querySelectorAll('a.auto_link_shortened')
        .forEach((anchor) {
      final fullLink = anchor.attributes['title'] ?? anchor.attributes['href'];
      if (fullLink != null) {
        anchor.innerHtml = fullLink;
      }
    });
    final rawHtml = classicContentElement.innerHtml;
    final innerDocument = html_parser.parse(rawHtml);
    final updatedText = innerDocument.body?.text.trim() ?? '';
    final newestContent = extractNewestContent(updatedText);
    return newestContent.isNotEmpty ? newestContent : 'No content';
  }
  return 'No content';
}
