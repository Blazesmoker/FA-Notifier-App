import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:fanotifier/features/submissions/data/submission_description_parser.dart';
import 'package:fanotifier/features/submissions/domain/submission_description_webview_content.dart';
import 'package:fanotifier/core/fa/fa_cookie_helper.dart';
import 'package:fanotifier/core/network/fa_http.dart';
import 'package:fanotifier/shared/fa/fa_theme_css_loader.dart';
import 'package:fanotifier/shared/utils/fa_icon_image_inliner.dart';

class SubmissionDescriptionService {
  SubmissionDescriptionService({
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
    return compute(extractSubmissionDescriptionHtmlWithBodyFallback, html);
  }

  Future<String> inlineIcons(String html) {
    return inlineFaIconUsernameImages(html);
  }

  Future<SubmissionDescriptionWebViewContent> buildWebViewContent(
    String html,
  ) async {
    return SubmissionDescriptionWebViewContent(
      html: html,
      faThemeCss: await loadFaThemeCss(),
    );
  }

  String findFullLink(String htmlSource, String truncatedUrl) {
    return findFullSubmissionAutoShortenedLink(htmlSource, truncatedUrl);
  }

  String plainText(String html) {
    return plainTextFromSubmissionHtml(html);
  }

  Future<String> fetchDescriptionHtml(String submissionId) async {
    final cookieA = await _secureStorage.read(key: 'fa_cookie_a');
    final cookieB = await _secureStorage.read(key: 'fa_cookie_b');

    if (cookieA == null || cookieB == null) {
      throw Exception('User not logged in or missing cookies.');
    }

    final url = 'https://www.furaffinity.net/view/$submissionId/';
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
      throw Exception(
        'Failed to fetch submission page: ${response.statusCode}',
      );
    }

    final decodedBody = utf8.decode(response.bodyBytes, allowMalformed: true);
    return compute(extractSubmissionDescriptionHtmlDefault, decodedBody);
  }
}
