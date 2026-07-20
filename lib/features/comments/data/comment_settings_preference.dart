import 'package:shared_preferences/shared_preferences.dart';

class CommentSettingsPreference {
  const CommentSettingsPreference();

  static const _collapsibleCommentsKey = 'comments_collapsible_enabled';

  Future<bool> loadCollapsibleComments() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(_collapsibleCommentsKey) ?? true;
  }

  Future<void> saveCollapsibleComments(bool value) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_collapsibleCommentsKey, value);
  }
}
