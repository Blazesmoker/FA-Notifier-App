import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

import 'package:fanotifier/features/notes/domain/note_reply_models.dart';

String? parseNewMessageKey(String html) {
  final document = html_parser.parse(html);
  return document
      .querySelector('form#note-form input[name="key"]')
      ?.attributes['value'];
}

NoteReplyForm? parseNoteReplyForm(Document document, Uri documentUri) {
  final form = document.querySelector('form#note-form');
  if (form == null || form.attributes['method']?.toLowerCase() != 'post') {
    return null;
  }
  final actionValue = form.attributes['action'];
  if (actionValue == null || actionValue.trim().isEmpty) {
    return null;
  }
  final actionUri = Uri.tryParse(actionValue);
  if (actionUri == null) {
    return null;
  }
  final action = documentUri.resolveUri(actionUri);
  if (action.scheme != 'https' ||
      action.host != 'www.furaffinity.net' ||
      action.port != 443 ||
      action.userInfo.isNotEmpty ||
      action.path != '/msg/send/') {
    return null;
  }
  final hiddenFields = <String, String>{};
  for (final input in form.querySelectorAll('input[type="hidden"][name]')) {
    final name = input.attributes['name']!;
    if (name.isEmpty || hiddenFields.containsKey(name)) {
      return null;
    }
    hiddenFields[name] = input.attributes['value'] ?? '';
  }
  if ((hiddenFields['key'] ?? '').trim().isEmpty ||
      form.querySelector('[name="to"]') == null ||
      form.querySelector('[name="subject"]') == null ||
      form.querySelector('textarea[name="message"]') == null) {
    return null;
  }
  return NoteReplyForm(
    action: action,
    documentUri: documentUri.removeFragment(),
    hiddenFields: hiddenFields,
  );
}
