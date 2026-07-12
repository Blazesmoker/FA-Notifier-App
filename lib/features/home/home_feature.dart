import 'package:FANotifier/features/home/data/home_login_webview_support_impl.dart';
import 'package:FANotifier/features/home/data/home_profile_repository_impl.dart';
import 'package:FANotifier/features/home/data/home_session_repository_impl.dart';
import 'package:FANotifier/features/home/data/shared_preferences_home_start_screen_preference_repository.dart';
import 'package:FANotifier/features/home/domain/home_login_webview_support.dart';
import 'package:FANotifier/features/home/domain/home_profile_repository.dart';
import 'package:FANotifier/features/home/domain/home_session_repository.dart';
import 'package:FANotifier/features/home/domain/home_start_screen_preference_repository.dart';

class HomeFeature {
  const HomeFeature._();

  static HomeSessionRepository createSessionRepository() {
    return HomeSessionRepositoryImpl.create();
  }

  static HomeProfileRepository createProfileRepository() {
    return HomeProfileRepositoryImpl();
  }

  static HomeLoginWebViewSupport createLoginWebViewSupport() {
    return const HomeLoginWebViewSupportImpl();
  }

  static HomeStartScreenPreferenceRepository
      createStartScreenPreferenceRepository() {
    return const SharedPreferencesHomeStartScreenPreferenceRepository();
  }
}
