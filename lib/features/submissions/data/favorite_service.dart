// lib/services/favorite_service.dart

import 'dart:async';
import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:FANotifier/shared/fa/fa_cookie_helper.dart';
import 'package:FANotifier/shared/fa/fa_http.dart';

/// Service to handle favorite/unfavorite operations with retry logic.
class FavoriteService {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    iOptions: IOSOptions( 
    accountName: 'flutter_secure_storage_service',
    accessibility: KeychainAccessibility.first_unlock),
  );
  final int maxRetries;
  final Duration retryInterval;

  FavoriteService({
    this.maxRetries = 5,
    this.retryInterval = const Duration(seconds: 2),
  });

  /// Execute a POST request with retries if it fails or times out.
  Future<bool> executePostWithRetry(String url) async {
    int attempt = 0;
    while (attempt < maxRetries) {
      try {
        final cookieHeader = await _getAuthCookies();
        if (cookieHeader.isEmpty) {
          debugPrint('DEBUG: Missing authentication cookies.');
          return false;
        }

        final response = await FAHttp.post(
          Uri.parse(url),
          headers: {
            HttpHeaders.cookieHeader: cookieHeader,
            'User-Agent': FAHttp.userAgent,
            'Content-Type': 'application/x-www-form-urlencoded',
          },
        );

        if (response.statusCode == 200 || response.statusCode == 302) {
          debugPrint('DEBUG: Successfully executed POST request to $url');
          return true;
        } else {
          debugPrint('DEBUG: Failed POST request to $url with status ${response.statusCode}');
        }
      } catch (e) {
        debugPrint('DEBUG: Exception during POST request to $url: $e');
      }

      attempt++;
      debugPrint('DEBUG: Retry attempt $attempt for $url after ${retryInterval.inSeconds} seconds.');
      await Future.delayed(retryInterval);
    }

    debugPrint('DEBUG: All retry attempts failed for $url');
    return false;
  }

  /// Retrieve authentication cookies needed for FA.
  Future<String> _getAuthCookies() async {
    // Typically 'a' and 'b' cookies for FurAffinity.
    final cookieA = await _secureStorage.read(key: 'fa_cookie_a');
    final cookieB = await _secureStorage.read(key: 'fa_cookie_b');
    if (cookieA == null || cookieA.isEmpty || cookieB == null || cookieB.isEmpty) {
      return '';
    }
    return FaCookieHelper.appendCfClearanceToCookieHeader('a=$cookieA; b=$cookieB');
  }
}
