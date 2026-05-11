import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'package:FANotifier/shared/fa/fa_cookie_helper.dart';
import 'package:FANotifier/shared/fa/fa_http.dart';

Future<bool> submitPostCommentOrReply({
  required FlutterSecureStorage secureStorage,
  required String message,
  String? submissionId,
  String? commentId,
}) async {
  final cookieA = await secureStorage.read(key: 'fa_cookie_a');
  final cookieB = await secureStorage.read(key: 'fa_cookie_b');

  String postUrl;
  Map<String, String> body;

  if (commentId != null) {
    postUrl = 'https://www.furaffinity.net/replyto/submission/$commentId/';
    body = {
      'reply': message,
      'send': 'Submit Comment',
      'comment': commentId,
      'name': '',
    };
  } else if (submissionId != null) {
    postUrl = 'https://www.furaffinity.net/view/$submissionId/';
    body = {
      'reply': message,
      'f': '0',
      'action': 'reply',
    };
  } else {
    return false;
  }

  final response = await http.post(
    Uri.parse(postUrl),
    headers: {
      'Cookie': await FaCookieHelper.appendCfClearanceToCookieHeader(
        'a=$cookieA; b=$cookieB',
      ),
      'User-Agent': FAHttp.userAgent,
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body: body,
  );

  debugPrint('Status Code: ${response.statusCode}');
  debugPrint('Response Body: ${response.body}');

  return response.statusCode == 302 ||
      response.body.contains('Your comment has been posted');
}

Future<bool> submitSubmissionReply({
  required FlutterSecureStorage secureStorage,
  required String message,
  String? submissionId,
  String? commentId,
  required bool isClassic,
}) async {
  final cookieA = await secureStorage.read(key: 'fa_cookie_a');
  final cookieB = await secureStorage.read(key: 'fa_cookie_b');
  if (cookieA == null || cookieB == null) return false;

  String postUrl;
  Map<String, String> body;

  if (isClassic) {
    postUrl = 'https://www.furaffinity.net/view/$submissionId/';
    body = {
      'action': 'replyto',
      'replyto': commentId ?? '',
      'reply': message,
      'submit': 'Post Comment',
    };
  } else {
    postUrl = 'https://www.furaffinity.net/replyto/submission/$commentId/';
    body = {
      'reply': message,
      'send': 'Submit Comment',
      'comment': commentId ?? '',
      'name': '',
    };
  }

  final response = await http.post(
    Uri.parse(postUrl),
    headers: {
      'Cookie': await FaCookieHelper.appendCfClearanceToCookieHeader(
        'a=$cookieA; b=$cookieB',
      ),
      'User-Agent': FAHttp.userAgent,
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body: body,
  );

  return response.statusCode == 302 ||
      response.body.contains('Your comment has been posted');
}
