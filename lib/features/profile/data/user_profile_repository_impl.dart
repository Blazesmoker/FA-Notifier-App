import 'package:fanotifier/features/profile/data/user_profile_api_service.dart';
import 'package:fanotifier/features/profile/data/user_profile_loader.dart';
import 'package:fanotifier/features/profile/data/user_profile_shout_deletion_coordinator.dart';
import 'package:fanotifier/features/profile/domain/shout.dart';
import 'package:fanotifier/features/profile/domain/user_profile_api_models.dart';
import 'package:fanotifier/features/profile/domain/user_profile_load_result.dart';
import 'package:fanotifier/features/profile/domain/user_profile_repository.dart';
import 'package:fanotifier/features/profile/domain/user_profile_shout_deletion_result.dart';

class UserProfileRepositoryImpl implements UserProfileRepository {
  UserProfileRepositoryImpl({UserProfileApiService? api})
      : _api = api ?? UserProfileApiService();

  final UserProfileApiService _api;

  @override
  Future<UserProfileLoadResult> loadProfile({
    required String nickname,
    required bool sfwEnabled,
  }) {
    return UserProfileLoader(api: _api).load(
      nickname: nickname,
      sfwEnabled: sfwEnabled,
    );
  }

  @override
  Future<AdditionalShoutsPayload?> loadAdditionalShouts({
    required String sanitizedUsername,
    required String? shoutPaginationKey,
    required int nextPage,
    required bool sfwEnabled,
    required Set<String> existingShoutIds,
  }) {
    return _api.fetchAdditionalShouts(
      sanitizedUsername: sanitizedUsername,
      shoutPaginationKey: shoutPaginationKey,
      nextPage: nextPage,
      sfwEnabled: sfwEnabled,
      existingShoutIds: existingShoutIds,
    );
  }

  @override
  Future<WatchUnwatchResult> updateWatchState({
    required String urlPath,
    required bool shouldWatch,
    required bool sfwEnabled,
  }) {
    return _api.sendWatchUnwatchRequest(
      urlPath,
      shouldWatch: shouldWatch,
      sfwEnabled: sfwEnabled,
    );
  }

  @override
  Future<BlockUnblockResult> updateBlockState({
    required String urlOrPath,
    required String keyValue,
    required bool shouldBlock,
    required bool usePost,
    required bool sfwEnabled,
    required String sanitizedUsername,
  }) {
    return _api.sendBlockUnblockRequest(
      urlOrPath,
      keyValue,
      shouldBlock: shouldBlock,
      usePost: usePost,
      sfwEnabled: sfwEnabled,
      sanitizedUsername: sanitizedUsername,
    );
  }

  @override
  Future<UserProfileShoutDeletionResult> deleteShouts({
    required List<Shout> shouts,
    required bool sfwEnabled,
  }) {
    return UserProfileShoutDeletionCoordinator(_api).delete(
      shouts: shouts,
      sfwEnabled: sfwEnabled,
    );
  }
}
