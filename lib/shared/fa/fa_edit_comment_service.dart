import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'package:FANotifier/shared/fa/fa_cookie_helper.dart';
import 'package:FANotifier/shared/fa/fa_edit_comment_parser.dart';
import 'package:FANotifier/shared/fa/fa_http.dart';

class EditCommentLoadResult {
  const EditCommentLoadResult({
    this.textarea,
    this.errorMessage,
  });

  final String? textarea;
  final String? errorMessage;
}

class EditCommentSubmitResult {
  const EditCommentSubmitResult({
    required this.success,
    this.errorMessage,
  });

  final bool success;
  final String? errorMessage;
}

class FaEditCommentService {
  FaEditCommentService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  void close() {
    _client.close();
  }

  Future<EditCommentLoadResult> loadEditCommentText({
    required String editLink,
    required String? cookieA,
    required String? cookieB,
  }) {
    return loadEditCommentTextWithClient(
      client: _client,
      editLink: editLink,
      cookieA: cookieA,
      cookieB: cookieB,
    );
  }

  Future<EditCommentSubmitResult> submitEditComment({
    required String editLink,
    required String? cookieA,
    required String? cookieB,
    required String updatedText,
    required bool requireFValue,
    required bool includeFValue,
    bool logFormDebug = false,
  }) {
    return submitEditCommentWithClient(
      client: _client,
      editLink: editLink,
      cookieA: cookieA,
      cookieB: cookieB,
      updatedText: updatedText,
      requireFValue: requireFValue,
      includeFValue: includeFValue,
      logFormDebug: logFormDebug,
    );
  }
}

Future<EditCommentLoadResult> loadEditCommentTextWithClient({
  required http.Client client,
  required String editLink,
  required String? cookieA,
  required String? cookieB,
}) async {
  try {
    final response = await client.get(
      Uri.parse(editLink),
      headers: await _editCommentHeaders(
        editLink: editLink,
        cookieA: cookieA,
        cookieB: cookieB,
      ),
    );

    if (response.statusCode != 200) {
      return const EditCommentLoadResult(
        errorMessage: 'Failed to load edit page',
      );
    }

    final textarea = parseEditCommentTextarea(response.body);

    if (textarea == null) {
      return const EditCommentLoadResult(
        errorMessage: 'BBCode textarea not found',
      );
    }

    return EditCommentLoadResult(textarea: textarea);
  } catch (e) {
    return EditCommentLoadResult(
      errorMessage: 'Error loading edit form: $e',
    );
  }
}

Future<EditCommentSubmitResult> submitEditCommentWithClient({
  required http.Client client,
  required String editLink,
  required String? cookieA,
  required String? cookieB,
  required String updatedText,
  required bool requireFValue,
  required bool includeFValue,
  bool logFormDebug = false,
}) async {
  try {
    final getResponse = await client.get(
      Uri.parse(editLink),
      headers: await _editCommentHeaders(
        editLink: editLink,
        cookieA: cookieA,
        cookieB: cookieB,
      ),
    );

    if (getResponse.statusCode != 200) {
      return EditCommentSubmitResult(
        success: false,
        errorMessage:
            'Failed to load edit page. Status code: ${getResponse.statusCode}',
      );
    }

    final form = parseEditCommentForm(
      getResponse.body,
      requireFValue: requireFValue,
    );

    if (logFormDebug) {
      debugPrint('TEST action: ${form?.action}');
      debugPrint('TEST comment_id: ${form?.commentId}');
      debugPrint('TEST key: ${form?.csrfKey}');
    }

    if (form == null) {
      return const EditCommentSubmitResult(
        success: false,
        errorMessage: 'Required form fields are missing.',
      );
    }

    final postUri = form.action.startsWith('http')
        ? Uri.parse(form.action)
        : Uri.parse('https://www.furaffinity.net${form.action}');

    final body = <String, String>{
      'action': 'edit-comment',
      'comment_id': form.commentId,
      'key': form.csrfKey,
    };

    if (includeFValue && form.fValue != null) {
      body['f'] = form.fValue!;
    }

    body['message'] = updatedText;
    body['mysubmit'] = 'Save';

    final postResponse = await client.post(
      postUri,
      headers: await _editCommentHeaders(
        editLink: editLink,
        cookieA: cookieA,
        cookieB: cookieB,
        includeContentType: true,
      ),
      body: body,
    );

    if (postResponse.statusCode == 302) {
      return const EditCommentSubmitResult(success: true);
    }

    return EditCommentSubmitResult(
      success: false,
      errorMessage:
          'Failed to update comment. Status code: ${postResponse.statusCode}',
    );
  } catch (error) {
    return EditCommentSubmitResult(
      success: false,
      errorMessage: 'An error occurred: $error',
    );
  }
}

Future<Map<String, String>> _editCommentHeaders({
  required String editLink,
  required String? cookieA,
  required String? cookieB,
  bool includeContentType = false,
}) async {
  final headers = <String, String>{
    'Cookie': await FaCookieHelper.appendCfClearanceToCookieHeader(
      'a=$cookieA; b=$cookieB',
    ),
    'User-Agent': FAHttp.userAgent,
    'Referer': editLink,
  };

  if (includeContentType) {
    headers['Content-Type'] = 'application/x-www-form-urlencoded';
  }

  return headers;
}
