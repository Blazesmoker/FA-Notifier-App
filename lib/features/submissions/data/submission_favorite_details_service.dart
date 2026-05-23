import 'dart:io';

import 'package:FANotifier/features/submissions/data/submission_favorite_links_parser.dart';
import 'package:FANotifier/shared/fa/fa_cookie_helper.dart';
import 'package:FANotifier/shared/fa/fa_http.dart';
import 'package:flutter/foundation.dart';

class SubmissionFavoriteDetailsService {
  const SubmissionFavoriteDetailsService();

  Future<SubmissionFavoriteLinks?> fetchLinksForSubmissionId({
    required String submissionId,
    required Future<String> Function() cookieHeaderProvider,
  }) {
    return fetchLinksForPostUrl(
      postUrl: 'https://www.furaffinity.net/view/$submissionId/',
      cookieHeaderProvider: cookieHeaderProvider,
      debugPostLabel: submissionId,
    );
  }

  Future<SubmissionFavoriteLinks?> fetchLinksForPostUrl({
    required String postUrl,
    required Future<String> Function() cookieHeaderProvider,
    String? debugPostLabel,
  }) async {
    final absolute = postUrl.startsWith('http')
        ? postUrl
        : 'https://www.furaffinity.net$postUrl';
    final cookie = await cookieHeaderProvider();
    if (cookie.isEmpty) return null;

    try {
      final response = await FAHttp.get(
        Uri.parse(absolute),
        headers: {
          HttpHeaders.cookieHeader:
              await FaCookieHelper.appendCfClearanceToCookieHeader(cookie),
          'User-Agent': FAHttp.userAgent,
        },
      );

      if (response.statusCode != 200) return null;

      final links = parseSubmissionFavoriteLinksFromHtml(response.body);

      if (!links.hasAnyUrl) {
        debugPrint('DEBUG: No fav/unfav URLs found for post: ${debugPostLabel ?? postUrl}');
      }

      return links;
    } catch (e) {
      debugPrint('Error fetching post details for ${debugPostLabel ?? postUrl}: $e');
      return null;
    }
  }
}
