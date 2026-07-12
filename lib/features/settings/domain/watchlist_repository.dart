import 'package:FANotifier/shared/fa/domain/user_link.dart';

abstract interface class WatchlistRepository {
  Future<String> buildCookieHeader();

  Future<List<UserLink>?> fetchUsersPage({
    required String title,
    required String sanitizedUsername,
    required int page,
    required String cookieHeader,
    required int maxRetries,
    required Duration retryDelay,
    void Function(String message)? onRetry,
  });
}
