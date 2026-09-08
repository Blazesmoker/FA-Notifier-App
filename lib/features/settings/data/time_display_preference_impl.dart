import 'package:fanotifier/features/settings/domain/time_display_preference.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TimeDisplayPreferenceImpl implements TimeDisplayPreference {
  const TimeDisplayPreferenceImpl();

  static const String _use24HourTimeKey = 'time_display_use_24_hour';

  @override
  Future<bool> loadUse24HourTime() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(_use24HourTimeKey) ?? false;
  }

  @override
  Future<void> saveUse24HourTime(bool value) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_use24HourTimeKey, value);
  }
}
