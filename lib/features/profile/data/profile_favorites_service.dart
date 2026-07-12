import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:FANotifier/core/preferences/sfw_mode_preference.dart';
import 'package:FANotifier/features/profile/domain/profile_favorites_repository.dart';
import 'package:FANotifier/features/profile/domain/profile_posts_parse_result.dart';
import 'package:FANotifier/features/profile/data/profile_posts_parser.dart';
import 'package:FANotifier/core/network/fa_http.dart';

class ProfileFavoritesService implements ProfileFavoritesRepository {
  ProfileFavoritesService({
    FlutterSecureStorage? secureStorage,
  }) : _secureStorage = secureStorage ??
            const FlutterSecureStorage(
              iOptions: IOSOptions(
                accountName: 'flutter_secure_storage_service',
                accessibility: KeychainAccessibility.first_unlock,
              ),
            );

  final FlutterSecureStorage _secureStorage;
  final SfwModePreference _sfwModePreference = SfwModePreference();

  @override
  String buildInitialFavoritesPageUrl(String username) {
    return 'https://www.furaffinity.net/favorites/$username/';
  }

  @override
  Future<ProfilePostsParseResult> fetchFavoritesPage(String url) async {
    final cookieHeader = await buildCookieHeader();
    final response = await FAHttp.get(
      Uri.parse(url),
      headers: {
        'Cookie': cookieHeader,
        'User-Agent': FAHttp.userAgent,
        'Referer': 'https://www.furaffinity.net',
      },
    );
    if (response.statusCode != 200) {
      throw Exception("Failed to load favorites: ${response.statusCode}");
    }

    final decodedBody = utf8.decode(response.bodyBytes, allowMalformed: true);
    return parseProfileFavoritePostsHtml(decodedBody, url);
  }

  @override
  Future<String> buildCookieHeader() async {
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
      String? cookieValue;
      if (name == 'sfw') {
        cookieValue = await _getSfwCookieValue();
      } else {
        cookieValue = await _secureStorage.read(key: 'fa_cookie_$name');
      }
      if (cookieValue != null && cookieValue.isNotEmpty) {
        cookies.add('$name=$cookieValue');
      }
    }
    return cookies.join('; ');
  }

  Future<String> _getSfwCookieValue() async {
    final sfwEnabled = await _sfwModePreference.loadSfwEnabled();
    return sfwEnabled ? '1' : '0';
  }
}
