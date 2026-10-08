import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:fanotifier/core/preferences/sfw_mode_preference.dart';
import 'package:fanotifier/features/profile/domain/profile_favorites_repository.dart';
import 'package:fanotifier/features/profile/domain/profile_posts_parse_result.dart';
import 'package:fanotifier/features/profile/data/profile_posts_parser.dart';
import 'package:fanotifier/core/network/fa_http.dart';

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
  Future<ProfilePostsParseResult> fetchFavoritesPage(
    String url, {
    bool Function()? isCancelled,
  }) async {
    final cookieHeader = await buildCookieHeader();
    final response = await FAHttp.get(
      Uri.parse(url),
      isCancelled: isCancelled,
      headers: {
        'Cookie': cookieHeader,
        'User-Agent': FAHttp.userAgent,
        'Referer': 'https://www.furaffinity.net',
      },
    );
    if (response.statusCode != 200) {
      throw Exception("Failed to load favorites: ${response.statusCode}");
    }

    if (isCancelled?.call() ?? false) {
      throw StateError('FA request cancelled');
    }
    final parsed = await parseProfileFavoritePostsPage(response.bodyBytes, url);
    if (isCancelled?.call() ?? false) {
      throw StateError('FA request cancelled');
    }
    return parsed;
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
