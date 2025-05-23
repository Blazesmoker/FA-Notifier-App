import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;

// Mapping from FA Timezone Names to IANA Timezones
final Map<String, String> faTimezoneToIana = {
  "International Date Line West": "Etc/GMT+12",
  "Samoa Standard Time": "Pacific/Pago_Pago",
  "Hawaiian Standard Time": "Pacific/Honolulu",
  "Alaskan Standard Time": "America/Anchorage",
  "Pacific Standard Time": "America/Los_Angeles",
  "Mountain Standard Time": "America/Denver",
  "Central Standard Time": "America/Chicago",
  "Eastern Standard Time": "America/New_York",
  "Caracas Standard Time": "America/Caracas",
  "Atlantic Standard Time": "America/Halifax",
  "Newfoundland Standard Time": "America/St_Johns",
  "Greenland Standard Time": "America/Godthab",
  "Mid-Atlantic Standard Time": "Etc/GMT-2",
  "Cape Verde Standard Time": "Atlantic/Cape_Verde",
  "Greenwich Mean Time": "Etc/GMT",
  "W. Europe Standard Time": "Europe/Berlin",
  "E. Europe Standard Time": "Europe/Minsk",
  "Russian Standard Time": "Europe/Moscow",
  "Iran Standard Time": "Asia/Tehran",
  "Arabian Standard Time": "Asia/Riyadh",
  "Afghanistan Standard Time": "Asia/Kabul",
  "West Asia Standard Time": "Asia/Tashkent",
  "India Standard Time": "Asia/Kolkata",
  "Nepal Standard Time": "Asia/Kathmandu",
  "Central Asia Standard Time": "Asia/Almaty",
  "Myanmar Standard Time": "Asia/Yangon",
  "North Asia Standard Time": "Asia/Krasnoyarsk",
  "North Asia East Standard Time": "Asia/Irkutsk",
  "Tokyo Standard Time": "Asia/Tokyo",
  "Cen. Australia Standard Time": "Australia/Adelaide",
  "West Pacific Standard Time": "Pacific/Port_Moresby",
  "Central Pacific Standard Time": "Pacific/Guadalcanal",
  "New Zealand Standard Time": "Pacific/Auckland",
};

class TimezoneProvider with ChangeNotifier {
  String _userTimezoneIanaName = 'Etc/UTC';
  bool _isDstCorrectionApplied = false;

  String get userTimezoneIanaName => _userTimezoneIanaName;
  bool get isDstCorrectionApplied => _isDstCorrectionApplied;

  /// Fetch timezone data from the FA settings page once.
  Future<void> fetchTimezone() async {
    final storage = const FlutterSecureStorage();
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
        'Cookie': 'a=$cookieA; b=$cookieB',
        'User-Agent': 'Mozilla/5.0 (compatible; FANotifier/1.0)',
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
