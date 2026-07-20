import 'package:fanotifier/features/home/domain/home_start_screen_preference.dart';

abstract interface class HomeStartScreenPreferenceRepository {
  Future<HomeStartScreenPreference> load();

  Future<void> save(HomeStartScreenPreference preference);
}
