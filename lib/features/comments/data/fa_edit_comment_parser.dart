import 'package:html/parser.dart' as html_parser;
import 'package:FANotifier/features/comments/domain/comment_edit_models.dart';

String? parseEditCommentTextarea(String html) {
  final document = html_parser.parse(html);
  return document.querySelector('textarea[name="message"]')?.text;
}

FaEditCommentFormData? parseEditCommentForm(
  String html, {
  required bool requireFValue,
}) {
  final document = html_parser.parse(html);
  final form = document.querySelector('form#edit_comment_form');
  if (form == null) return null;

  final action = form.attributes['action'];
  final commentId =
      form.querySelector('input[name="comment_id"]')?.attributes['value'];
  final csrfKey = form.querySelector('input[name="key"]')?.attributes['value'];
  final fValue = form.querySelector('input[name="f"]')?.attributes['value'];

  if (action == null || commentId == null || csrfKey == null) {
    return null;
  }
  if (requireFValue && fValue == null) {
    return null;
  }

  return FaEditCommentFormData(
    action: action,
    commentId: commentId,
    csrfKey: csrfKey,
    fValue: fValue,
  );
}
