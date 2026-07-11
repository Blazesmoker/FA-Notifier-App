import 'package:FANotifier/features/profile/data/user_profile_api_service.dart';
import 'package:FANotifier/features/profile/domain/shout.dart';
import 'package:FANotifier/features/profile/domain/user_profile_api_models.dart';
import 'package:FANotifier/features/profile/domain/user_profile_shout_deletion_result.dart';

class UserProfileShoutDeletionCoordinator {
  const UserProfileShoutDeletionCoordinator(this._api);

  final UserProfileApiService _api;

  Future<UserProfileShoutDeletionResult> delete({
    required List<Shout> shouts,
    required bool sfwEnabled,
  }) async {
    final resolvedShouts = await _api.resolveControlsShouts(
      shouts: shouts,
      sfwEnabled: sfwEnabled,
    );
    if (resolvedShouts.length != shouts.length) {
      return const UserProfileShoutDeletionResult(
        status: UserProfileShoutDeletionStatus.unmatched,
      );
    }

    final shoutIdsByPage = <int, List<String>>{};
    for (final resolvedShout in resolvedShouts) {
      shoutIdsByPage.putIfAbsent(resolvedShout.page, () => <String>[]);
      shoutIdsByPage[resolvedShout.page]!.add(resolvedShout.id);
    }
    final pages = shoutIdsByPage.keys.toList()
      ..sort((first, second) => second.compareTo(first));
    var anySuccess = false;
    DeleteShoutResult? failedResult;

    for (final page in pages) {
      final result = await _api.deleteShouts(
        shoutIds: shoutIdsByPage[page]!,
        sfwEnabled: sfwEnabled,
        page: page,
      );
      if (result.success) {
        anySuccess = true;
        continue;
      }
      failedResult = result;
      break;
    }

    if (failedResult?.missingCookies == true) {
      return const UserProfileShoutDeletionResult(
        status: UserProfileShoutDeletionStatus.missingCookies,
      );
    }
    if (failedResult == null) {
      return const UserProfileShoutDeletionResult(
        status: UserProfileShoutDeletionStatus.success,
      );
    }
    if (anySuccess) {
      return const UserProfileShoutDeletionResult(
        status: UserProfileShoutDeletionStatus.partialFailure,
      );
    }
    return UserProfileShoutDeletionResult(
      status: UserProfileShoutDeletionStatus.failure,
      error: failedResult.error,
    );
  }
}
