import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:FANotifier/features/profile/domain/profile_gallery_favorite_repository.dart';
import 'package:FANotifier/core/fa/fa_cookie_helper.dart';
import 'package:FANotifier/core/network/fa_http.dart';

class ProfileGalleryFavoriteRepositoryImpl
    implements ProfileGalleryFavoriteRepository {
  ProfileGalleryFavoriteRepositoryImpl._();

  static final ProfileGalleryFavoriteRepositoryImpl _instance =
      ProfileGalleryFavoriteRepositoryImpl._();

  factory ProfileGalleryFavoriteRepositoryImpl() => _instance;

  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage(
    iOptions: IOSOptions(
      accountName: 'flutter_secure_storage_service',
      accessibility: KeychainAccessibility.first_unlock,
    ),
  );

  final Map<String, Timer> _debounceTimers = <String, Timer>{};
  final Map<String, bool> _pendingFavStates = <String, bool>{};

  @override
  Future<bool> hasAuthCookies() async {
    final cookieA = await _secureStorage.read(key: 'fa_cookie_a');
    final cookieB = await _secureStorage.read(key: 'fa_cookie_b');
    return cookieA != null &&
        cookieA.isNotEmpty &&
        cookieB != null &&
        cookieB.isNotEmpty;
  }

  Future<void> _executePostWithRetry(String url) async {
    debugPrint('[FAV SERVICE] Starting executePostWithRetry => $url');
    final cookieA = await _secureStorage.read(key: 'fa_cookie_a');
    final cookieB = await _secureStorage.read(key: 'fa_cookie_b');
    if (cookieA == null ||
        cookieA.isEmpty ||
        cookieB == null ||
        cookieB.isEmpty) {
      debugPrint('[FAV SERVICE] Missing auth cookies for POST request.');
      return;
    }

    int attempts = 0;
    const maxAttempts = 5;
    while (attempts < maxAttempts) {
      try {
        final response = await FAHttp.post(
          Uri.parse(url),
          headers: {
            'Cookie': await FaCookieHelper.appendCfClearanceToCookieHeader(
              'a=$cookieA; b=$cookieB',
            ),
            'User-Agent': FAHttp.userAgent,
            'Referer': 'https://www.furaffinity.net',
          },
        );
        debugPrint(
          '[FAV SERVICE] POST => $url, status: ${response.statusCode}',
        );
        if (response.statusCode == 302) {
          debugPrint('[FAV SERVICE] Success => $url');
          return;
        }
        debugPrint(
          '[FAV SERVICE] Failed with status: ${response.statusCode}, retrying...',
        );
      } catch (error) {
        debugPrint('[FAV SERVICE] Error => $url, will retry. $error');
      }
      attempts++;
      if (attempts < maxAttempts) {
        await Future<void>.delayed(const Duration(seconds: 3));
      } else {
        debugPrint('[FAV SERVICE] Max retry attempts reached for $url');
      }
    }
  }

  @override
  void toggleFavorite({
    required String uniqueNumber,
    required bool isFav,
    required String? favUrl,
    required String? unfavUrl,
    void Function(String uniqueNumber, bool finalState)? onPostComplete,
  }) {
    debugPrint('[FAV SERVICE] toggleFavorite($uniqueNumber, isFav=$isFav)');
    _pendingFavStates[uniqueNumber] = isFav;
    _debounceTimers[uniqueNumber]?.cancel();
    _debounceTimers[uniqueNumber] =
        Timer(const Duration(seconds: 3), () async {
      final finalState = _pendingFavStates[uniqueNumber];
      if (finalState == null) return;

      _pendingFavStates.remove(uniqueNumber);
      _debounceTimers.remove(uniqueNumber);

      final urlToUse = finalState ? favUrl : unfavUrl;
      if (urlToUse == null || urlToUse.isEmpty) {
        debugPrint(
          '[FAV SERVICE] No valid URL found for $uniqueNumber => cannot POST.',
        );
        return;
      }

      debugPrint('[FAV SERVICE] Debounce ended => POSTing $urlToUse');
      await _executePostWithRetry(urlToUse);
      onPostComplete?.call(uniqueNumber, finalState);
    });
  }

  @override
  void cancelAll() {
    for (final timer in _debounceTimers.values) {
      timer.cancel();
    }
    _debounceTimers.clear();
    _pendingFavStates.clear();
    debugPrint('[FAV SERVICE] cancelAll() called.');
  }
}
