import 'package:fanotifier/features/profile/data/user_profile_api_service.dart';
import 'package:fanotifier/features/profile/data/user_profile_loader.dart';
import 'package:fanotifier/features/profile/data/user_profile_shout_deletion_coordinator.dart';
import 'package:fanotifier/features/profile/domain/shout.dart';
import 'package:fanotifier/features/profile/domain/user_profile_api_models.dart';
import 'package:fanotifier/features/profile/domain/user_profile_load_result.dart';
import 'package:fanotifier/features/profile/domain/user_profile_repository.dart';
import 'package:fanotifier/features/profile/domain/user_profile_shout_deletion_result.dart';
import 'package:fanotifier/shared/fa/domain/fa_author_watch_state_store.dart';

class UserProfileRepositoryImpl implements UserProfileRepository {
  UserProfileRepositoryImpl({
    UserProfileApiService? api,
    required this._authorWatchStateStore,
  }) : _api = api ?? UserProfileApiService();

  final UserProfileApiService _api;
  final FaAuthorWatchStateStore _authorWatchStateStore;

  @override
  Future<UserProfileLoadResult> loadProfile({
    required String nickname,
    required bool sfwEnabled,
  }) async {
    final watchRevision = _authorWatchStateStore.revision;
    final result = await UserProfileLoader(api: _api).load(
      nickname: nickname,
      sfwEnabled: sfwEnabled,
    );
    if (result.parsed.hasRealUserProfile) {
      _authorWatchStateStore.write(
        result.sanitizedUsername,
        FaAuthorWatchState(
          isWatching: result.parsed.isWatching,
          watchLink: result.parsed.watchLink,
          unwatchLink: result.parsed.unwatchLink,
          isBlocked: result.parsed.isBlocked,
        ),
        expectedRevision: watchRevision,
      );
    }
    return result;
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
    final segments = Uri.parse(urlPath).pathSegments;
    if (segments.length > 1) {
      _authorWatchStateStore.invalidate(segments[1]);
    }
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
    _authorWatchStateStore.invalidate(sanitizedUsername);
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

  @override
  Future<DeleteShoutResult> deleteOwnShoutFromProfile({
    required Shout shout,
    required String sanitizedProfileUsername,
    required bool sfwEnabled,
  }) {
    return _api.deleteOwnShoutFromProfile(
      shout: shout,
      sanitizedProfileUsername: sanitizedProfileUsername,
      sfwEnabled: sfwEnabled,
    );
  }
}
