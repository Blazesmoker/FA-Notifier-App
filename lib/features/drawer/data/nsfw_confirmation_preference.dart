import 'package:shared_preferences/shared_preferences.dart';

import 'package:fanotifier/features/drawer/domain/nsfw_confirmation_repository.dart';

class NsfwConfirmationPreference implements NsfwConfirmationRepository {
  static const _disabledKey = 'nsfwConfirmationDisabled';

  @override
  Future<bool> loadDisabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_disabledKey) ?? false;
  }

  @override
  Future<void> saveDisabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_disabledKey, value);
  }
}
