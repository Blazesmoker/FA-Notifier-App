// favorite_gallery_service.dart

import 'dart:async';
import 'package:http/http.dart' as http;

/// A singleton service to handle favorite/unfavorite actions:
/// - 3-second debounce to prevent spam.
/// - Retries on the final POST request every 2 seconds, up to 10 tries.
class FavoriteGalleryService {
  FavoriteGalleryService._internal();

  static final FavoriteGalleryService _instance = FavoriteGalleryService._internal();

  factory FavoriteGalleryService() => _instance;

  /// Stores debounce timers for each submission's "toggle" action.
  final Map<String, Timer> _debounceTimers = {};

  /// Desired final fav states (true = fav, false = unfav) for each submission.
  final Map<String, bool> _pendingFavStates = {};

  /// Executes a POST request with retries every 2 seconds, up to 10 tries.
  Future<void> executePostWithRetry(String url, String cookieA, String cookieB) async {
    print('[FAV SERVICE] Starting executePostWithRetry => $url');
    int attempts = 0;
    const maxAttempts = 10;
    while (attempts < maxAttempts) {
      try {
        final response = await http.post(
          Uri.parse(url),
          headers: {
            'Cookie': 'a=$cookieA; b=$cookieB',
            'User-Agent': 'Mozilla/5.0',
            'Referer': 'https://www.furaffinity.net',
          },
        );
        print('[FAV SERVICE] POST => $url, status: ${response.statusCode}');
        if (response.statusCode == 302) {
          print('[FAV SERVICE] Success => $url');
          return;
        } else {
          print('[FAV SERVICE] Failed with status: ${response.statusCode}, retrying...');
        }
      } catch (e) {
        print('[FAV SERVICE] Error => $url, will retry. $e');
      }
      attempts++;
      if (attempts < maxAttempts) {
        // Wait 2 seconds before next retry.
        await Future.delayed(const Duration(seconds: 2));
      } else {
        print('[FAV SERVICE] Max retry attempts reached for $url');
      }
    }
  }


  void toggleFavorite({
    required String uniqueNumber,
    required bool isFav,
    required String? favUrl,
    required String? unfavUrl,
    required String cookieA,
    required String cookieB,
    void Function(String uniqueNumber, bool finalState)? onPostComplete,
  }) {
    print('[FAV SERVICE] toggleFavorite($uniqueNumber, isFav=$isFav)');


    _pendingFavStates[uniqueNumber] = isFav;

    // Cancel any existing timer for this submission.
    _debounceTimers[uniqueNumber]?.cancel();

    // Start a new debounce timer.
    _debounceTimers[uniqueNumber] = Timer(const Duration(seconds: 3), () async {
      final finalState = _pendingFavStates[uniqueNumber];
      if (finalState == null) return;


      _pendingFavStates.remove(uniqueNumber);
      _debounceTimers.remove(uniqueNumber);


      String? urlToUse = finalState ? favUrl : unfavUrl;
      if (urlToUse == null || urlToUse.isEmpty) {
        print('[FAV SERVICE] No valid URL found for $uniqueNumber => cannot POST.');
        return;
      }

      print('[FAV SERVICE] Debounce ended => POSTing $urlToUse');

      await executePostWithRetry(urlToUse, cookieA, cookieB);


      if (onPostComplete != null) {
        onPostComplete(uniqueNumber, finalState);
      }
    });
  }

  /// Cancels all pending timers.
  void cancelAll() {
    for (var timer in _debounceTimers.values) {
      timer.cancel();
    }
    _debounceTimers.clear();
    _pendingFavStates.clear();
    print('[FAV SERVICE] cancelAll() called.');
  }
}
