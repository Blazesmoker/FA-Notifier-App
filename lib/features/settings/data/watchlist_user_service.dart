import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:FANotifier/features/profile/domain/user_link.dart';
import 'package:FANotifier/features/settings/data/watchlist_user_parser.dart';
import 'package:FANotifier/shared/fa/fa_cookie_helper.dart';
import 'package:FANotifier/shared/fa/fa_http.dart';

typedef WatchlistRetryCallback = void Function(String message);

String buildWatchlistPageUrl({
  required String title,
  required String sanitizedUsername,
  required int page,
}) {
  final route = title == 'Recent Watchers' ? 'to' : 'by';
  return 'https://www.furaffinity.net/watchlist/$route/$sanitizedUsername?page=$page';
}

Future<String> buildWatchlistCookieHeader(
  [FlutterSecureStorage? secureStorage]
) async {
  final storage = secureStorage ?? _defaultSecureStorage();
  final cookieA = await storage.read(key: 'fa_cookie_a');
  final cookieB = await storage.read(key: 'fa_cookie_b');

  if (cookieA == null || cookieB == null) {
    return '';
  }

  return FaCookieHelper.appendCfClearanceToCookieHeader(
    'a=$cookieA; b=$cookieB',
  );
}

Future<List<UserLink>?> fetchWatchlistUsersPage({
  required String title,
  required String sanitizedUsername,
  required int page,
  required String cookieHeader,
  required int maxRetries,
  required Duration retryDelay,
  WatchlistRetryCallback? onRetry,
}) async {
  for (int attempt = 1; attempt <= maxRetries; attempt++) {
    if (attempt > 1) {
      onRetry?.call('Retrying page $page ($attempt/$maxRetries)...');
    }

    try {
      final response = await http.get(
        Uri.parse(
          buildWatchlistPageUrl(
            title: title,
            sanitizedUsername: sanitizedUsername,
            page: page,
          ),
        ),
        headers: {
          'Cookie': cookieHeader,
          'User-Agent': FAHttp.userAgent,
        },
      );

      if (response.statusCode == 200) {
        return parseWatchlistUsers(response.body);
      }
    } catch (_) {}

    if (attempt < maxRetries) {
      await Future.delayed(retryDelay);
    }
  }

  return null;
}

FlutterSecureStorage _defaultSecureStorage() {
  return const FlutterSecureStorage(
    iOptions: IOSOptions(
      accountName: 'flutter_secure_storage_service',
      accessibility: KeychainAccessibility.first_unlock,
    ),
  );
}
