import 'package:shared_preferences/shared_preferences.dart';

enum HomeStartScreenPreference {
  browse,
  submissions,
  profile,
}

const String homeStartScreenPreferenceKey = 'home_start_screen_preference';

HomeStartScreenPreference homeStartScreenPreferenceFromStorage(String? value) {
  switch (value) {
    case 'submissions':
      return HomeStartScreenPreference.submissions;
    case 'profile':
      return HomeStartScreenPreference.profile;
    case 'browse':
    default:
      return HomeStartScreenPreference.browse;
  }
}

extension HomeStartScreenPreferenceLabel on HomeStartScreenPreference {
  String get storageValue {
    switch (this) {
      case HomeStartScreenPreference.submissions:
        return 'submissions';
      case HomeStartScreenPreference.profile:
        return 'profile';
      case HomeStartScreenPreference.browse:
        return 'browse';
    }
  }

  String get title {
    switch (this) {
      case HomeStartScreenPreference.submissions:
        return 'Submissions';
      case HomeStartScreenPreference.profile:
        return 'Main profile';
      case HomeStartScreenPreference.browse:
        return 'Browse';
    }
  }

  String get subtitle {
    switch (this) {
      case HomeStartScreenPreference.submissions:
        return 'Open the Submissions screen when the app starts.';
      case HomeStartScreenPreference.profile:
        return 'Open your main profile when the app starts.';
      case HomeStartScreenPreference.browse:
        return 'Open the Browse screen when the app starts.';
    }
  }
}

Future<HomeStartScreenPreference> loadHomeStartScreenPreference() async {
  final prefs = await SharedPreferences.getInstance();
  return homeStartScreenPreferenceFromStorage(
    prefs.getString(homeStartScreenPreferenceKey),
  );
}

Future<void> saveHomeStartScreenPreference(
  HomeStartScreenPreference preference,
) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(
    homeStartScreenPreferenceKey,
    preference.storageValue,
  );
}
