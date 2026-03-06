import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../services/fa_cookie_helper.dart';
import '../services/fa_http.dart';

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

  final response = await http.post(
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
