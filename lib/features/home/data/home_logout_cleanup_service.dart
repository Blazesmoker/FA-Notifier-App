import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import 'package:fanotifier/features/home/data/home_auth_cookie_service.dart';
import 'package:fanotifier/features/home/data/home_profile_cache.dart';
import 'package:fanotifier/features/home/data/home_session_preference.dart';

class HomeLogoutCleanupService {
  HomeLogoutCleanupService({
    required HomeAuthCookieService authCookieService,
    required HomeSessionPreference sessionPreference,
    required HomeProfileCache profileCache,
  })  : _authCookieService = authCookieService,
        _sessionPreference = sessionPreference,
        _profileCache = profileCache;

  final HomeAuthCookieService _authCookieService;
  final HomeSessionPreference _sessionPreference;
  final HomeProfileCache _profileCache;

  Future<void> clearLocalSession() async {
    await _authCookieService.clearWebViewCookies();
    debugPrint('[Logout] All cookies deleted.');
    await _authCookieService.clearStoredCookies();
    debugPrint('[Logout] FlutterSecureStorage cleared.');
    await _sessionPreference.clearAll();
    await _profileCache.clear();
    await DefaultCacheManager().emptyCache();
    debugPrint('[Logout] Image cache cleared.');
  }
}
