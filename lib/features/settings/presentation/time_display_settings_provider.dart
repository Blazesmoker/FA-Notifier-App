import 'package:fanotifier/features/settings/domain/time_display_preference.dart';
import 'package:flutter/foundation.dart';

class TimeDisplaySettingsProvider with ChangeNotifier {
  TimeDisplaySettingsProvider({
    required TimeDisplayPreference preference,
  }) : _preference = preference {
    _load();
  }

  final TimeDisplayPreference _preference;
  bool _use24HourTime = false;

  bool get use24HourTime => _use24HourTime;

  Future<void> _load() async {
    _use24HourTime = await _preference.loadUse24HourTime();
    notifyListeners();
  }

  Future<void> setUse24HourTime(bool value) async {
    if (_use24HourTime == value) return;
    _use24HourTime = value;
    notifyListeners();
    await _preference.saveUse24HourTime(value);
  }
}
