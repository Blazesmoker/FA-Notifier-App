import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:FANotifier/shared/fa/fa_cookie_helper.dart';
import 'package:FANotifier/shared/fa/fa_http.dart';
import 'package:FANotifier/shared/fa/fa_timezone_to_iana.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TimezoneProvider with ChangeNotifier {
  static const String _timezoneCacheKey = 'fa_timezone.iana_name';
  static const String _dstCacheKey = 'fa_timezone.dst_correction';
  static const String _lastCheckedCacheKey = 'fa_timezone.last_checked_ms';
  static const Duration _refreshInterval = Duration(days: 14);

  String _userTimezoneIanaName = 'Etc/UTC';
  bool _isDstCorrectionApplied = false;

  String get userTimezoneIanaName => _userTimezoneIanaName;
  bool get isDstCorrectionApplied => _isDstCorrectionApplied;

  Future<void> fetchTimezone() async {
    final prefs = await SharedPreferences.getInstance();
    final cachedTimezone = (prefs.getString(_timezoneCacheKey) ?? '').trim();
    final cachedDst = prefs.getBool(_dstCacheKey);
    final lastCheckedMs = prefs.getInt(_lastCheckedCacheKey);
    final now = DateTime.now();
    final hasCachedTimezone = cachedTimezone.isNotEmpty;
    if (hasCachedTimezone) {
      _userTimezoneIanaName = cachedTimezone;
      _isDstCorrectionApplied = cachedDst ?? false;
      notifyListeners();
      if (lastCheckedMs != null) {
        final lastChecked =
            DateTime.fromMillisecondsSinceEpoch(lastCheckedMs);
        if (now.difference(lastChecked) < _refreshInterval) {
          return;
        }
      }
    }

    final storage = const FlutterSecureStorage(
      iOptions: IOSOptions( 
    accountName: 'flutter_secure_storage_service',
    accessibility: KeychainAccessibility.first_unlock),
    );
    String? cookieA = await storage.read(key: 'fa_cookie_a');
    String? cookieB = await storage.read(key: 'fa_cookie_b');
    if (cookieA == null || cookieB == null) {
      if (!hasCachedTimezone) {
        _userTimezoneIanaName = 'Etc/UTC';
        _isDstCorrectionApplied = false;
        notifyListeners();
      }
      return;
    }

    final settingsUrl = 'https://www.furaffinity.net/controls/settings/';
    final response = await FAHttp.get(
      Uri.parse(settingsUrl),
      headers: {
        'Cookie': await FaCookieHelper.appendCfClearanceToCookieHeader(
          'a=$cookieA; b=$cookieB',
        ),
        'User-Agent': FAHttp.userAgent,
      },
    );

    if (response.statusCode == 200) {
      var document = html_parser.parse(response.body);
      var timezoneSelect = document.querySelector('select[name="timezone"]');
      if (timezoneSelect != null) {
        var selectedOption = timezoneSelect.querySelector('option[selected="selected"]');
        if (selectedOption != null) {
          String timezoneText = selectedOption.text.trim();
          RegExp regex = RegExp(r'\[.*\]\s*(.*)');
          Match? match = regex.firstMatch(timezoneText);
          if (match != null) {
            String timezoneName = match.group(1) ?? '';
            _userTimezoneIanaName = faTimezoneToIana[timezoneName] ?? 'Etc/UTC';
          } else {
            _userTimezoneIanaName = 'Etc/UTC';
          }
        } else {
          _userTimezoneIanaName = 'Etc/UTC';
        }
      } else {
        _userTimezoneIanaName = 'Etc/UTC';
      }

      var timezoneDstCheckbox = document.querySelector('input[name="timezone_dst"]');
      if (timezoneDstCheckbox != null) {
        _isDstCorrectionApplied = timezoneDstCheckbox.attributes.containsKey('checked');
      } else {
        _isDstCorrectionApplied = false;
      }
      await prefs.setString(_timezoneCacheKey, _userTimezoneIanaName);
      await prefs.setBool(_dstCacheKey, _isDstCorrectionApplied);
      await prefs.setInt(
        _lastCheckedCacheKey,
        now.millisecondsSinceEpoch,
      );
    } else {
      if (!hasCachedTimezone) {
        _userTimezoneIanaName = 'Etc/UTC';
        _isDstCorrectionApplied = false;
      }
    }
    notifyListeners();
  }
}
