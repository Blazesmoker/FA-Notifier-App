import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'package:FANotifier/core/preferences/sfw_mode_preference.dart';
import 'package:FANotifier/features/profile/data/profile_journals_parser.dart';
import 'package:FANotifier/features/profile/domain/profile_journals_models.dart';
import 'package:FANotifier/shared/fa/fa_http.dart';

class ProfileJournalsService {
  ProfileJournalsService({
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

  Future<ProfileJournalsPageData> fetchJournalsPage({
    required String username,
    required int pageNumber,
  }) async {
    final cookieHeader = await _getAllCookies();

    final url = pageNumber == 1
        ? 'https://www.furaffinity.net/journals/$username/'
        : 'https://www.furaffinity.net/journals/$username/$pageNumber/';

    final response = await http.get(
      Uri.parse(url),
      headers: {
        'Cookie': cookieHeader,
        'User-Agent': FAHttp.userAgent,
        'Referer': 'https://www.furaffinity.net',
      },
    );

    if (response.statusCode == 200) {
      final parsed = parseProfileJournalsHtml(response.body);
      return ProfileJournalsPageData(
        journals: parsed.journals,
        hasMore: parsed.hasMore,
      );
    }

    debugPrint('Response body: ${response.body}');
    throw Exception(
      'ProfileJournals: Failed to load journals: ${response.statusCode}',
    );
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
    ];

    final cookies = <String>[];

    for (final name in cookieNames) {
      final storageKey = 'fa_cookie_$name';
      final value = await _secureStorage.read(key: storageKey);
      if (value != null && value.isNotEmpty) {
        cookies.add('$name=$value');
      }
    }

    if (await _loadSfwEnabled()) {
      cookies.add('sfw=1');
    }

    return cookies.join('; ');
  }

  Future<bool> _loadSfwEnabled() async {
    return _sfwModePreference.loadSfwEnabled();
  }
}
