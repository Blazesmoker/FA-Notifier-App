import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'package:FANotifier/features/profile/data/user_description_parser.dart';
import 'package:FANotifier/shared/fa/fa_cookie_helper.dart';
import 'package:FANotifier/shared/fa/fa_http.dart';

class UserDescriptionService {
  UserDescriptionService({
    FlutterSecureStorage? secureStorage,
  }) : _secureStorage = secureStorage ??
            const FlutterSecureStorage(
              iOptions: IOSOptions(
                accountName: 'flutter_secure_storage_service',
                accessibility: KeychainAccessibility.first_unlock,
              ),
            );

  final FlutterSecureStorage _secureStorage;

  Future<String> fetchCleanHtml(String sanitizedUsername) async {
    final cookieA = await _secureStorage.read(key: 'fa_cookie_a');
    final cookieB = await _secureStorage.read(key: 'fa_cookie_b');

    if (cookieA == null || cookieB == null) {
      throw Exception('User not logged in or missing cookies.');
    }

    final url = 'https://www.furaffinity.net/user/$sanitizedUsername/';
    final response = await http.get(
      Uri.parse(url),
      headers: {
        'Cookie': await FaCookieHelper.appendCfClearanceToCookieHeader(
          'a=$cookieA; b=$cookieB',
        ),
        'User-Agent': FAHttp.userAgent,
      },
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to fetch user page: ${response.statusCode}');
    }

    final decodedBody = utf8.decode(response.bodyBytes, allowMalformed: true);
    return compute(extractUserDescriptionHtmlDefault, decodedBody);
  }
}
