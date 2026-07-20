import 'package:shared_preferences/shared_preferences.dart';

import 'package:fanotifier/features/home/domain/home_start_screen_preference.dart';
import 'package:fanotifier/features/home/domain/home_start_screen_preference_repository.dart';

class SharedPreferencesHomeStartScreenPreferenceRepository
    implements HomeStartScreenPreferenceRepository {
  const SharedPreferencesHomeStartScreenPreferenceRepository();

  static const String _key = 'home_start_screen_preference';

  @override
  Future<HomeStartScreenPreference> load() async {
    final prefs = await SharedPreferences.getInstance();
    switch (prefs.getString(_key)) {
      case 'submissions':
        return HomeStartScreenPreference.submissions;
      case 'profile':
        return HomeStartScreenPreference.profile;
      case 'browse':
      default:
        return HomeStartScreenPreference.browse;
    }
  }

  @override
  Future<void> save(HomeStartScreenPreference preference) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, _storageValue(preference));
  }

  String _storageValue(HomeStartScreenPreference preference) {
    switch (preference) {
      case HomeStartScreenPreference.submissions:
        return 'submissions';
      case HomeStartScreenPreference.profile:
        return 'profile';
      case HomeStartScreenPreference.browse:
        return 'browse';
    }
  }
}
