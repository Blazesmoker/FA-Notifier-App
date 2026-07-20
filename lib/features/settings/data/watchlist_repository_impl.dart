import 'package:fanotifier/shared/fa/domain/user_link.dart';
import 'package:fanotifier/features/settings/data/watchlist_user_service.dart';
import 'package:fanotifier/features/settings/domain/watchlist_repository.dart';

class WatchlistRepositoryImpl implements WatchlistRepository {
  const WatchlistRepositoryImpl();

  @override
  Future<String> buildCookieHeader() {
    return buildWatchlistCookieHeader();
  }

  @override
  Future<List<UserLink>?> fetchUsersPage({
    required String title,
    required String sanitizedUsername,
    required int page,
    required String cookieHeader,
    required int maxRetries,
    required Duration retryDelay,
    void Function(String message)? onRetry,
  }) {
    return fetchWatchlistUsersPage(
      title: title,
      sanitizedUsername: sanitizedUsername,
      page: page,
      cookieHeader: cookieHeader,
      maxRetries: maxRetries,
      retryDelay: retryDelay,
      onRetry: onRetry,
    );
  }
}
