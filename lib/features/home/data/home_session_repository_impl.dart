import 'package:fanotifier/features/home/data/home_auth_cookie_service.dart';
import 'package:fanotifier/features/home/data/home_logout_cleanup_service.dart';
import 'package:fanotifier/features/home/data/home_profile_cache.dart';
import 'package:fanotifier/features/home/data/home_session_preference.dart';
import 'package:fanotifier/features/home/domain/home_session_repository.dart';
import 'package:fanotifier/shared/fa/domain/user_profile.dart';

class HomeSessionRepositoryImpl implements HomeSessionRepository {
  factory HomeSessionRepositoryImpl.create() {
    const authCookieService = HomeAuthCookieService();
    final sessionPreference = HomeSessionPreference();
    const profileCache = HomeProfileCache();
    return HomeSessionRepositoryImpl(
      authCookieService: authCookieService,
      sessionPreference: sessionPreference,
      profileCache: profileCache,
      logoutCleanupService: HomeLogoutCleanupService(
        authCookieService: authCookieService,
        sessionPreference: sessionPreference,
        profileCache: profileCache,
      ),
    );
  }

  const HomeSessionRepositoryImpl({
    required this._authCookieService,
    required this._sessionPreference,
    required this._profileCache,
    required this._logoutCleanupService,
  });

  final HomeAuthCookieService _authCookieService;
  final HomeSessionPreference _sessionPreference;
  final HomeProfileCache _profileCache;
  final HomeLogoutCleanupService _logoutCleanupService;

  @override
  Future<bool> loadIsLoggedIn() {
    return _sessionPreference.loadIsLoggedIn();
  }

  @override
  Future<void> saveIsLoggedIn(bool value) {
    return _sessionPreference.saveIsLoggedIn(value);
  }

  @override
  Future<UserProfile?> loadCachedUserProfile() {
    return _profileCache.load();
  }

  @override
  Future<void> saveCachedUserProfile(UserProfile profile) {
    return _profileCache.save(profile);
  }

  @override
  Future<bool> hasWebViewAuthCookie() {
    return _authCookieService.hasWebViewAuthCookie();
  }

  @override
  Future<void> saveCookiesFromWebView() {
    return _authCookieService.saveCookiesFromWebView();
  }

  @override
  Future<void> setStoredCookies() {
    return _authCookieService.setStoredCookies();
  }

  @override
  Future<void> setSfwCookieToNsfw() {
    return _authCookieService.setSfwCookieToNsfw();
  }

  @override
  Future<void> clearLocalSession() {
    return _logoutCleanupService.clearLocalSession();
  }
}
