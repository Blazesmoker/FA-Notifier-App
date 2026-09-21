import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart' show Color, Colors;
import 'package:fanotifier/features/profile/domain/shout.dart';
import 'package:fanotifier/features/profile/domain/user_profile_repository.dart';
import 'package:fanotifier/features/profile/domain/user_profile_shout_deletion_result.dart';
import 'user_profile_controller.dart';
import 'user_profile_shout_selection_controller.dart';

class UserProfileShoutsController {
  UserProfileShoutsController({
    required UserProfileRepository repository,
    required this._profileController,
    required UserProfileShoutSelectionController selectionController,
    required this._isMounted,
    required this._fetchUserProfile,
    required this._exitShoutSelectionMode,
    required this._showMessage,
  }) : _profileRepository = repository,
       _shoutSelectionController = selectionController;

  final UserProfileRepository _profileRepository;
  final UserProfileController _profileController;
  final UserProfileShoutSelectionController _shoutSelectionController;
  final bool Function() _isMounted;
  final Future<void> Function() _fetchUserProfile;
  final VoidCallback _exitShoutSelectionMode;
  final void Function(String, {required Color color}) _showMessage;
  final ValueNotifier<bool> _isLoadingMoreShouts = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _isDeletingSelectedShouts = ValueNotifier<bool>(
    false,
  );
  final ValueNotifier<int> _shoutsRevision = ValueNotifier<int>(0);

  ValueListenable<bool> get isLoadingMore => _isLoadingMoreShouts;

  ValueListenable<bool> get isDeleting => _isDeletingSelectedShouts;

  ValueListenable<int> get revision => _shoutsRevision;

  void reconcileShouts() {
    _shoutSelectionController.reconcile(_profileController.shouts);
    _shoutsRevision.value++;
  }

  void dispose() {
    _isLoadingMoreShouts.dispose();
    _shoutsRevision.dispose();
    _isDeletingSelectedShouts.dispose();
  }

  Future<void> deleteOwnShoutFromOtherProfile(Shout shout) async {
    if (_isDeletingSelectedShouts.value || shout.ownShoutDeleteUrl == null) {
      return;
    }

    final loadedProfilePage = _profileController.currentShoutPage;
    _isDeletingSelectedShouts.value = true;

    try {
      final result = await _profileRepository.deleteOwnShoutFromProfile(
        shout: shout,
        sanitizedProfileUsername: _profileController.sanitizedUsername,
        sfwEnabled: _profileController.sfwEnabled,
      );
      if (!_isMounted()) return;

      if (result.missingCookies) {
        _showMessage(
          'Please log in to perform this action.',
          color: Colors.red,
        );
      } else if (result.success) {
        _showMessage('Shout deleted.', color: Colors.green);
        await _fetchUserProfile();
        await _restoreLoadedShoutPages(loadedProfilePage);
      } else if (result.error != null) {
        _showMessage(
          'The delete result could not be confirmed. Refresh the profile before trying again.',
          color: Colors.red,
        );
      } else {
        _showMessage('Failed to delete shout.', color: Colors.red);
      }
    } catch (_) {
      if (!_isMounted()) return;
      _showMessage(
        'The delete result could not be confirmed. Refresh the profile before trying again.',
        color: Colors.red,
      );
    } finally {
      if (_isMounted()) {
        _isDeletingSelectedShouts.value = false;
      }
    }
  }

  Future<void> deleteShouts(List<Shout> shoutsToDelete) async {
    if (shoutsToDelete.isEmpty || _isDeletingSelectedShouts.value) {
      return;
    }

    final loadedProfilePage = _profileController.currentShoutPage;

    _isDeletingSelectedShouts.value = true;

    try {
      final deletionResult = await _profileRepository.deleteShouts(
        shouts: shoutsToDelete,
        sfwEnabled: _profileController.sfwEnabled,
      );

      if (!_isMounted()) return;
      if (deletionResult.status == UserProfileShoutDeletionStatus.unmatched) {
        _showMessage(
          "Failed to match one or more selected shouts on the controls page.",
          color: Colors.red,
        );
        return;
      }

      if (deletionResult.status ==
          UserProfileShoutDeletionStatus.missingCookies) {
        _showMessage(
          "Please log in to perform this action.",
          color: Colors.red,
        );
      } else if (deletionResult.status ==
          UserProfileShoutDeletionStatus.success) {
        final deletedCount = shoutsToDelete.length;
        _showMessage(
          deletedCount == 1
              ? "Shout deleted."
              : "$deletedCount shouts deleted.",
          color: Colors.green,
        );
        _exitShoutSelectionMode();
        await _fetchUserProfile();
        await _restoreLoadedShoutPages(loadedProfilePage);
      } else if (deletionResult.status ==
          UserProfileShoutDeletionStatus.partialFailure) {
        _showMessage(
          "Some selected shouts were deleted, but one page failed.",
          color: Colors.red,
        );
        _exitShoutSelectionMode();
        await _fetchUserProfile();
        await _restoreLoadedShoutPages(loadedProfilePage);
      } else if (deletionResult.error != null) {
        _showMessage("Error: ${deletionResult.error}", color: Colors.red);
      } else {
        _showMessage("Failed to delete shout.", color: Colors.red);
      }
    } catch (e) {
      if (!_isMounted()) return;
      _showMessage("Error: $e", color: Colors.red);
    } finally {
      if (_isMounted()) {
        _isDeletingSelectedShouts.value = false;
      }
    }
  }

  Future<void> _restoreLoadedShoutPages(int targetPage) async {
    while (_isMounted() &&
        _profileController.currentShoutPage < targetPage &&
        _profileController.currentShoutPage <
            _profileController.totalShoutPages) {
      await loadMoreShouts();
    }
  }

  Future<void> loadMoreShouts() async {
    if (_isLoadingMoreShouts.value ||
        _profileController.currentShoutPage >=
            _profileController.totalShoutPages) {
      debugPrint(
        "Cannot load more shouts. Loading: ${_isLoadingMoreShouts.value}, Current: ${_profileController.currentShoutPage}, Total: ${_profileController.totalShoutPages}",
      );
      return;
    }

    _isLoadingMoreShouts.value = true;

    try {
      final nextPage = _profileController.currentShoutPage + 1;
      final payload = await _profileRepository.loadAdditionalShouts(
        sanitizedUsername: _profileController.sanitizedUsername,
        shoutPaginationKey: _profileController.shoutPaginationKey,
        nextPage: nextPage,
        sfwEnabled: _profileController.sfwEnabled,
        existingShoutIds: _profileController.shouts
            .map((shout) => shout.id)
            .toSet(),
      );

      if (!_isMounted()) return;
      if (payload == null) {
        debugPrint("Missing shout pagination key; cannot load more shouts.");
        return;
      }

      _profileController.addShouts(payload);
      _shoutSelectionController.reconcile(_profileController.shouts);
      _shoutsRevision.value++;
    } catch (e) {
      debugPrint('Error loading more shouts: $e');
      if (!_isMounted()) return;
      _showMessage('Failed to load more shouts', color: Colors.red);
    } finally {
      if (_isMounted()) {
        _isLoadingMoreShouts.value = false;
      }
    }
  }
}
