// lib/services/favorite_service.dart

import 'dart:async';
import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

/// Service to handle favorite/unfavorite operations with retry logic.
class FavoriteService {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
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
          print('DEBUG: Missing authentication cookies.');
          return false;
        }

        final response = await http.post(
          Uri.parse(url),
          headers: {
            HttpHeaders.cookieHeader: cookieHeader,
            'User-Agent': 'Mozilla/5.0 (compatible; FANotifier/1.0)',
            'Content-Type': 'application/x-www-form-urlencoded',
          },
        );

        if (response.statusCode == 200 || response.statusCode == 302) {
          print('DEBUG: Successfully executed POST request to $url');
          return true;
        } else {
          print('DEBUG: Failed POST request to $url with status ${response.statusCode}');
        }
      } catch (e) {
        print('DEBUG: Exception during POST request to $url: $e');
      }

      attempt++;
      print('DEBUG: Retry attempt $attempt for $url after ${retryInterval.inSeconds} seconds.');
      await Future.delayed(retryInterval);
    }

    print('DEBUG: All retry attempts failed for $url');
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
    return 'a=$cookieA; b=$cookieB';
  }
}
