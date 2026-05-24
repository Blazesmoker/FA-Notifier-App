import 'package:shared_preferences/shared_preferences.dart';

class NotesFirstRunPreference {
  static const _didFirstRunKey = 'did_first_run_skip';

  Future<bool> loadDidFirstRunSkip() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_didFirstRunKey) ?? false;
  }

  Future<void> setFirstRunSkipDone() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_didFirstRunKey, true);
  }
}
