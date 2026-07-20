import 'package:fanotifier/features/profile/domain/shout.dart';
import 'package:fanotifier/features/profile/domain/user_profile_api_models.dart';
import 'package:fanotifier/features/profile/domain/user_profile_load_result.dart';
import 'package:fanotifier/features/profile/domain/user_profile_shout_deletion_result.dart';

abstract class UserProfileRepository {
  Future<UserProfileLoadResult> loadProfile({
    required String nickname,
    required bool sfwEnabled,
  });

  Future<AdditionalShoutsPayload?> loadAdditionalShouts({
    required String sanitizedUsername,
    required String? shoutPaginationKey,
    required int nextPage,
    required bool sfwEnabled,
    required Set<String> existingShoutIds,
  });

  Future<WatchUnwatchResult> updateWatchState({
    required String urlPath,
    required bool shouldWatch,
    required bool sfwEnabled,
  });

  Future<BlockUnblockResult> updateBlockState({
    required String urlOrPath,
    required String keyValue,
    required bool shouldBlock,
    required bool usePost,
    required bool sfwEnabled,
    required String sanitizedUsername,
  });

  Future<UserProfileShoutDeletionResult> deleteShouts({
    required List<Shout> shouts,
    required bool sfwEnabled,
  });
}
