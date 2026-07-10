import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:FANotifier/features/profile/data/user_description_parser.dart';
import 'package:FANotifier/features/profile/domain/user_description_webview_content.dart';
import 'package:FANotifier/shared/fa/fa_cookie_helper.dart';
import 'package:FANotifier/shared/fa/fa_http.dart';
import 'package:FANotifier/shared/fa/fa_theme_css_loader.dart';
import 'package:FANotifier/shared/utils/fa_icon_image_inliner.dart';

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

  Future<String> extractInitialHtml(String html) {
    return compute(extractUserDescriptionHtmlWithBodyFallback, html);
  }

  Future<String> inlineIcons(String html) {
    return inlineFaIconUsernameImages(html);
  }

  Future<UserDescriptionWebViewContent> buildWebViewContent(
    String html,
  ) async {
    return UserDescriptionWebViewContent(
      html: html,
      faThemeCss: await loadFaThemeCss(),
    );
  }

  String findFullLink(String htmlSource, String truncatedUrl) {
    return findFullAutoShortenedLink(htmlSource, truncatedUrl) ?? truncatedUrl;
  }

  String plainText(String html) {
    return plainTextFromHtml(html);
  }

  Future<String> fetchCleanHtml(String sanitizedUsername) async {
    final cookieA = await _secureStorage.read(key: 'fa_cookie_a');
    final cookieB = await _secureStorage.read(key: 'fa_cookie_b');

    if (cookieA == null || cookieB == null) {
      throw Exception('User not logged in or missing cookies.');
    }

    final url = 'https://www.furaffinity.net/user/$sanitizedUsername/';
    final response = await FAHttp.get(
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
