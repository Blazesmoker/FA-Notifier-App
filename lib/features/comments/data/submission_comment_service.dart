import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:FANotifier/core/fa/fa_cookie_helper.dart';
import 'package:FANotifier/core/network/fa_http.dart';
import 'package:FANotifier/shared/fa/domain/submission_comment_repository.dart';

String extractClassicSubmissionCommentReplyId(String input) {
  final regex = RegExp(r'/replyto/submission/(\d+)/');
  final match = regex.firstMatch(input);
  return match != null ? match.group(1)! : input;
}

class PostCommentService implements SubmissionCommentRepository {
  PostCommentService({
    FlutterSecureStorage? secureStorage,
  }) : _secureStorage = secureStorage ??
            const FlutterSecureStorage(
              iOptions: IOSOptions(
                accountName: 'flutter_secure_storage_service',
                accessibility: KeychainAccessibility.first_unlock,
              ),
            );

  final FlutterSecureStorage _secureStorage;

  @override
  Future<bool> submitComment({
    required String message,
    required String submissionId,
  }) {
    return submitPostCommentOrReply(
      secureStorage: _secureStorage,
      message: message,
      submissionId: submissionId,
    );
  }

  Future<bool> submitReply({
    required String message,
    required String submissionId,
    required String? commentId,
    required bool isClassic,
  }) {
    return submitSubmissionReply(
      secureStorage: _secureStorage,
      message: message,
      submissionId: submissionId,
      commentId: commentId,
      isClassic: isClassic,
    );
  }

  @override
  String? resolveReplyId({
    required String replyLink,
    required String? commentId,
    required bool isClassic,
  }) {
    return isClassic
        ? extractClassicSubmissionCommentReplyId(replyLink)
        : commentId;
  }
}

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

  final response = await FAHttp.post(
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

  final response = await FAHttp.post(
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
