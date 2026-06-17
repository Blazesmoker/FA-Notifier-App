import 'package:shared_preferences/shared_preferences.dart';

import 'package:FANotifier/features/profile/domain/user_profile.dart';

class HomeProfileCache {
  const HomeProfileCache();

  static const String _usernameKey = 'home_profile_cache.username';
  static const String _avatarUrlKey = 'home_profile_cache.avatar_url';
  static const String _profileUrlKey = 'home_profile_cache.profile_url';

  Future<UserProfile?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final username = (prefs.getString(_usernameKey) ?? '').trim();
    final avatarUrl = (prefs.getString(_avatarUrlKey) ?? '').trim();
    final profileUrl = (prefs.getString(_profileUrlKey) ?? '').trim();
    if (username.isEmpty && avatarUrl.isEmpty && profileUrl.isEmpty) {
      return null;
    }
    return UserProfile(
      username: username.isEmpty ? 'Username' : username,
      profileImageUrl: avatarUrl,
      profileUrl: profileUrl.isEmpty ? null : profileUrl,
    );
  }

  Future<void> save(UserProfile profile) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_usernameKey, profile.username);
    await prefs.setString(_avatarUrlKey, profile.profileImageUrl);
    final profileUrl = profile.profileUrl;
    if (profileUrl == null || profileUrl.isEmpty) {
      await prefs.remove(_profileUrlKey);
    } else {
      await prefs.setString(_profileUrlKey, profileUrl);
    }
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_usernameKey);
    await prefs.remove(_avatarUrlKey);
    await prefs.remove(_profileUrlKey);
  }
}
