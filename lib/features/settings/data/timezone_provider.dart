import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import 'package:FANotifier/shared/fa/fa_cookie_helper.dart';
import 'package:FANotifier/shared/fa/fa_http.dart';
import 'package:FANotifier/shared/fa/fa_timezone_to_iana.dart';

class TimezoneProvider with ChangeNotifier {
  String _userTimezoneIanaName = 'Etc/UTC';
  bool _isDstCorrectionApplied = false;

  String get userTimezoneIanaName => _userTimezoneIanaName;
  bool get isDstCorrectionApplied => _isDstCorrectionApplied;

  /// Fetch timezone data from the FA settings page once.
  Future<void> fetchTimezone() async {
    final storage = const FlutterSecureStorage(
      iOptions: IOSOptions( 
    accountName: 'flutter_secure_storage_service',
    accessibility: KeychainAccessibility.first_unlock),
    );
    String? cookieA = await storage.read(key: 'fa_cookie_a');
    String? cookieB = await storage.read(key: 'fa_cookie_b');
    if (cookieA == null || cookieB == null) {
      // Not logged in – use default UTC.
      _userTimezoneIanaName = 'Etc/UTC';
      _isDstCorrectionApplied = false;
      notifyListeners();
      return;
    }

    final settingsUrl = 'https://www.furaffinity.net/controls/settings/';
    final response = await http.get(
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
    } else {
      _userTimezoneIanaName = 'Etc/UTC';
      _isDstCorrectionApplied = false;
    }
    notifyListeners();
  }
}
