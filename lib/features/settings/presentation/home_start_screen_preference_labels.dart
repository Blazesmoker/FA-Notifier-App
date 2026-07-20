import 'package:fanotifier/features/home/domain/home_start_screen_preference.dart';

extension HomeStartScreenPreferenceLabel on HomeStartScreenPreference {
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
