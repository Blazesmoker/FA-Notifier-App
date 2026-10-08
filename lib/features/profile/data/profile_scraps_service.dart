import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:fanotifier/core/preferences/sfw_mode_preference.dart';
import 'package:fanotifier/features/profile/domain/profile_scraps_repository.dart';
import 'package:fanotifier/features/profile/domain/profile_posts_parse_result.dart';
import 'package:fanotifier/features/profile/data/profile_posts_parser.dart';
import 'package:fanotifier/core/network/fa_http.dart';

class ProfileScrapsService implements ProfileScrapsRepository {
  ProfileScrapsService({
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
  String buildInitialScrapsPageUrl(String username) {
    return 'https://www.furaffinity.net/scraps/$username/';
  }

  @override
  Future<ProfilePostsParseResult> fetchScrapsPage(
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
      throw Exception("Failed to load scraps: ${response.statusCode}");
    }

    if (isCancelled?.call() ?? false) {
      throw StateError('FA request cancelled');
    }
    final parsed = await parseProfileScrapsPostsPage(response.bodyBytes, url);
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
    final sfwEnabled = await _sfwModePreference.loadSfwEnabled();
    return sfwEnabled ? '1' : '0';
  }
}
