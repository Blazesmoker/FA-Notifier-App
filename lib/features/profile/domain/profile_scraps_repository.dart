import 'package:FANotifier/features/profile/domain/profile_posts_parse_result.dart';

abstract interface class ProfileScrapsRepository {
  String buildInitialScrapsPageUrl(String username);

  Future<ProfilePostsParseResult> fetchScrapsPage(String url);

  Future<String> buildCookieHeader();
}
