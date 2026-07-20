import 'package:fanotifier/features/profile/data/user_profile_api_service.dart';
import 'package:fanotifier/features/profile/domain/user_profile_load_result.dart';
import 'package:flutter/foundation.dart';

class UserProfileLoader {
  const UserProfileLoader({required UserProfileApiService api}) : _api = api;

  final UserProfileApiService _api;

  Future<UserProfileLoadResult> load({
    required String nickname,
    required bool sfwEnabled,
  }) async {
    final payload = await _api.fetchProfile(
      nickname: nickname,
      sfwEnabled: sfwEnabled,
    );
    final parsed = await compute(parseUserProfileHtml, payload.htmlBody);
    final shouldShowDescription = parsed.hasRealUserProfile &&
        parsed.userDescription != null &&
        parsed.userDescription!.trim().isNotEmpty;

    return UserProfileLoadResult(
      sanitizedUsername: payload.sanitizedUsername,
      parsed: parsed,
      shouldShowDescription: shouldShowDescription,
    );
  }
}
