import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:FANotifier/features/profile/domain/profile_posts_parse_result.dart';
import 'package:FANotifier/features/profile/data/profile_posts_parser.dart';
import 'package:FANotifier/features/submissions/data/submission_favorite_links_parser.dart';
import 'package:FANotifier/shared/fa/fa_http.dart';

class ProfileScrapsService {
  ProfileScrapsService({required FlutterSecureStorage secureStorage})
      : _secureStorage = secureStorage;

  final FlutterSecureStorage _secureStorage;

  Future<ProfilePostsParseResult> fetchScrapsPage(String url) async {
    final cookieHeader = await _getAllCookies();
    final response = await http.get(
      Uri.parse(url),
      headers: {
        'Cookie': cookieHeader,
        'User-Agent': FAHttp.userAgent,
        'Referer': 'https://www.furaffinity.net',
      },
    );
    if (response.statusCode != 200) {
      throw Exception("Failed to load scraps: ${response.statusCode}");
    }

    final decodedBody = utf8.decode(response.bodyBytes, allowMalformed: true);
    return parseProfileScrapsPostsHtml(decodedBody, url);
  }

  Future<SubmissionFavoriteLinks?> fetchPostFavoriteLinks(
    String uniqueNumber,
  ) async {
    final postUrl = 'https://www.furaffinity.net/view/$uniqueNumber/';
    final cookieHeader = await _getAllCookies();
    final response = await http.get(
      Uri.parse(postUrl),
      headers: {
        'Cookie': cookieHeader,
        'User-Agent': FAHttp.userAgent,
      },
    );
    if (response.statusCode == 200) {
      return parseSubmissionFavoriteLinksFromHtml(response.body);
    }
    return null;
  }

  Future<String> _getAllCookies() async {
    final cookieNames = [
      'a',
      'b',
      'cc',
      'cf_clearance',
      'folder',
      'nodesc',
      'sz',
      'sfw',
    ];
    final cookies = <String>[];
    for (final name in cookieNames) {
      if (name == 'sfw') {
        final sfwValue = await _getSfwCookieValue();
        cookies.add('sfw=$sfwValue');
      } else {
        final storageKey = 'fa_cookie_$name';
        final value = await _secureStorage.read(key: storageKey);
        if (value != null && value.isNotEmpty) {
          cookies.add('$name=$value');
        }
      }
    }
    return cookies.join('; ');
  }

  Future<String> _getSfwCookieValue() async {
    final prefs = await SharedPreferences.getInstance();
    final sfwEnabled = prefs.getBool('sfwEnabled') ?? true;
    return sfwEnabled ? '1' : '0';
  }
}
