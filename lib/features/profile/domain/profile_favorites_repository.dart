import 'package:FANotifier/features/profile/domain/profile_posts_parse_result.dart';

abstract interface class ProfileFavoritesRepository {
  String buildInitialFavoritesPageUrl(String username);

  Future<ProfilePostsParseResult> fetchFavoritesPage(String url);

  Future<String> buildCookieHeader();
}
