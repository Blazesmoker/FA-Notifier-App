import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:html/parser.dart' as html_parser;

import 'package:FANotifier/shared/fa/fa_cookie_helper.dart';
import 'package:FANotifier/shared/fa/fa_http.dart';

class JournalCommentService {
  JournalCommentService({
    FlutterSecureStorage? secureStorage,
  }) : _secureStorage = secureStorage ??
            const FlutterSecureStorage(
              iOptions: IOSOptions(
                accountName: 'flutter_secure_storage_service',
                accessibility: KeychainAccessibility.first_unlock,
              ),
            );

  final FlutterSecureStorage _secureStorage;

  Future<bool> submitComment({
    required String message,
    required String journalId,
  }) {
    return submitJournalCommentOrReply(
      secureStorage: _secureStorage,
      message: message,
      journalId: journalId,
    );
  }

  Future<bool> submitReplyToComment({
    required String message,
    required String journalId,
    required String commentId,
  }) {
    return submitJournalReplyToComment(
      secureStorage: _secureStorage,
      message: message,
      submissionId: journalId,
      commentId: commentId,
    );
  }
}

Future<bool> submitJournalCommentOrReply({
  required FlutterSecureStorage secureStorage,
  required String message,
  required String journalId,
  String? replyToId,
}) async {
  final cookieA = await secureStorage.read(key: 'fa_cookie_a');
  final cookieB = await secureStorage.read(key: 'fa_cookie_b');

  if (cookieA == null || cookieB == null) {
    debugPrint('Error: Authentication cookies are missing.');
    return false;
  }

  final response = await FAHttp.post(
    Uri.parse('https://www.furaffinity.net/journal/$journalId/'),
    headers: {
      'Cookie': await FaCookieHelper.appendCfClearanceToCookieHeader(
        'a=$cookieA; b=$cookieB',
      ),
      'User-Agent': FAHttp.userAgent,
      'Content-Type': 'application/x-www-form-urlencoded',
      'Accept':
          'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'Accept-Encoding': 'gzip, deflate, br',
      'Accept-Language': 'en-US,en;q=0.5',
    },
    body: {
      'action': 'reply',
      'replyto': replyToId ?? '',
      'reply': message,
      'submit': 'Post Comment',
    },
  );

  debugPrint('Status Code: ${response.statusCode}');

  return response.statusCode == 302 ||
      (response.statusCode == 200 &&
          response.body.contains('Your comment has been posted'));
}

Future<bool> submitJournalReplyToComment({
  required FlutterSecureStorage secureStorage,
  required String message,
  required String submissionId,
  required String commentId,
}) async {
  final sanitized = commentId
      .replaceFirst('#cid:', '')
      .replaceFirst('cid:', '')
      .trim();

  if (!RegExp(r'^\d+$').hasMatch(sanitized)) {
    throw Exception('Invalid comment ID.');
  }

  final cookieA = await secureStorage.read(key: 'fa_cookie_a');
  final cookieB = await secureStorage.read(key: 'fa_cookie_b');

  if (cookieA == null || cookieB == null) {
    throw Exception('Not authenticated.');
  }

  final postUrl = 'https://www.furaffinity.net/journal/$submissionId/';

  final resp = await FAHttp.post(
    Uri.parse(postUrl),
    headers: {
      'Cookie': await FaCookieHelper.appendCfClearanceToCookieHeader(
        'a=$cookieA; b=$cookieB',
      ),
      'User-Agent': FAHttp.userAgent,
      'Content-Type': 'application/x-www-form-urlencoded',
      'Referer': '$postUrl#cid:$sanitized',
    },
    body: {
      'action': 'replyto',
      'replyto': sanitized,
      'reply': message,
      'submit': 'Post Comment',
    },
  );

  if (resp.statusCode == 302) return true;
  if (resp.statusCode == 200 &&
      resp.body.contains('Your comment has been posted')) {
    return true;
  }

  if (resp.statusCode == 200) {
    final doc = html_parser.parse(resp.body);
    throw Exception(
      doc.querySelector('.error_message_class')?.text ?? 'Unknown error',
    );
  }

  return false;
}
