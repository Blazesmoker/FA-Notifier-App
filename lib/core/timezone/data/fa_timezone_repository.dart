import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:FANotifier/core/timezone/domain/timezone_repository.dart';
import 'package:FANotifier/core/timezone/domain/timezone_settings.dart';
import 'package:FANotifier/core/fa/fa_cookie_helper.dart';
import 'package:FANotifier/core/network/fa_http.dart';
import 'package:FANotifier/core/timezone/data/fa_timezone_to_iana.dart';

class FaTimezoneRepository implements TimezoneRepository {
  const FaTimezoneRepository({
    FlutterSecureStorage? secureStorage,
  }) : _secureStorage = secureStorage ??
            const FlutterSecureStorage(
              iOptions: IOSOptions(
                accountName: 'flutter_secure_storage_service',
                accessibility: KeychainAccessibility.first_unlock,
              ),
            );

  static const String _timezoneCacheKey = 'fa_timezone.iana_name';
  static const String _dstCacheKey = 'fa_timezone.dst_correction';
  static const String _lastCheckedCacheKey = 'fa_timezone.last_checked_ms';
  final FlutterSecureStorage _secureStorage;

  @override
  Future<CachedTimezoneSettings?> loadCached() async {
    final preferences = await SharedPreferences.getInstance();
    final timezone =
        (preferences.getString(_timezoneCacheKey) ?? '').trim();
    if (timezone.isEmpty) return null;
    final lastCheckedMs = preferences.getInt(_lastCheckedCacheKey);
    return CachedTimezoneSettings(
      settings: TimezoneSettings(
        ianaName: timezone,
        isDstCorrectionApplied:
            preferences.getBool(_dstCacheKey) ?? false,
      ),
      lastChecked: lastCheckedMs == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(lastCheckedMs),
    );
  }

  @override
  Future<TimezoneRemoteResult> fetchRemote() async {
    final cookieA = await _secureStorage.read(key: 'fa_cookie_a');
    final cookieB = await _secureStorage.read(key: 'fa_cookie_b');
    if (cookieA == null || cookieB == null) {
      return const TimezoneRemoteResult.notAuthenticated();
    }

    final response = await FAHttp.get(
      Uri.parse('https://www.furaffinity.net/controls/settings/'),
      headers: {
        'Cookie': await FaCookieHelper.appendCfClearanceToCookieHeader(
          'a=$cookieA; b=$cookieB',
        ),
        'User-Agent': FAHttp.userAgent,
      },
    );
    if (response.statusCode != 200) {
      return const TimezoneRemoteResult.unavailable();
    }

    final document = html_parser.parse(response.body);
    final selectedOption = document
        .querySelector('select[name="timezone"]')
        ?.querySelector('option[selected="selected"]');
    var ianaName = 'Etc/UTC';
    if (selectedOption != null) {
      final timezoneText = selectedOption.text.trim();
      final match = RegExp(r'\[.*\]\s*(.*)').firstMatch(timezoneText);
      if (match != null) {
        final timezoneName = match.group(1) ?? '';
        ianaName = faTimezoneToIana[timezoneName] ?? 'Etc/UTC';
      }
    }

    final dstCheckbox =
        document.querySelector('input[name="timezone_dst"]');
    return TimezoneRemoteResult.success(
      TimezoneSettings(
        ianaName: ianaName,
        isDstCorrectionApplied:
            dstCheckbox?.attributes.containsKey('checked') ?? false,
      ),
    );
  }

  @override
  Future<void> save(TimezoneSettings settings, DateTime checkedAt) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_timezoneCacheKey, settings.ianaName);
    await preferences.setBool(
      _dstCacheKey,
      settings.isDstCorrectionApplied,
    );
    await preferences.setInt(
      _lastCheckedCacheKey,
      checkedAt.millisecondsSinceEpoch,
    );
  }
}
