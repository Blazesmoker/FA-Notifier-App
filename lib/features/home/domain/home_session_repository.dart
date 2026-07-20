import 'package:fanotifier/shared/fa/domain/user_profile.dart';

abstract interface class HomeSessionRepository {
  Future<bool> loadIsLoggedIn();

  Future<void> saveIsLoggedIn(bool value);

  Future<UserProfile?> loadCachedUserProfile();

  Future<void> saveCachedUserProfile(UserProfile profile);

  Future<bool> hasWebViewAuthCookie();

  Future<void> saveCookiesFromWebView();

  Future<void> setStoredCookies();

  Future<void> setSfwCookieToNsfw();

  Future<void> clearLocalSession();
}
