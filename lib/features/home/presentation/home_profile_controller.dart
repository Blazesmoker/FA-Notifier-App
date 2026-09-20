import 'package:flutter/foundation.dart';
import 'package:fanotifier/features/home/domain/home_profile_repository.dart';
import 'package:fanotifier/features/home/domain/home_session_repository.dart';
import 'package:fanotifier/shared/fa/domain/user_profile.dart';

class HomeProfileController {
  HomeProfileController({
    required HomeProfileRepository profileRepository,
    required HomeSessionRepository sessionRepository,
    required this._isMounted,
    required this._updateState,
    required this._onProfileLoaded,
  }) : _homeProfileRepository = profileRepository,
       _homeSessionRepository = sessionRepository;

  final HomeProfileRepository _homeProfileRepository;
  final HomeSessionRepository _homeSessionRepository;
  final bool Function() _isMounted;
  final void Function(VoidCallback) _updateState;
  final VoidCallback _onProfileLoaded;
  UserProfile? _userProfile;
  bool _isLoadingProfile = true;
  String? _startupHomeHtml;

  UserProfile? get userProfile => _userProfile;
  bool get isLoadingProfile => _isLoadingProfile;

  void setStartupHomeHtml(String? html) {
    _startupHomeHtml = html;
  }

  void clearProfile() {
    _userProfile = null;
    _isLoadingProfile = false;
  }

  Future<void> loadCachedUserProfile() async {
    final cachedProfile = await _homeSessionRepository.loadCachedUserProfile();
    if (!_isMounted() || cachedProfile == null) return;
    _updateState(() {
      _userProfile = cachedProfile;
      _isLoadingProfile = false;
    });
    _onProfileLoaded();
  }

  Future<void> fetchUserProfile() async {
    try {
      final startupHomeHtml = _startupHomeHtml;
      _startupHomeHtml = null;
      UserProfile? profile = await _homeProfileRepository.fetchUserProfile(
        homeHtml: startupHomeHtml,
      );
      if (profile != null) {
        await _homeSessionRepository.saveCachedUserProfile(profile);
      }
      if (!_isMounted()) return;
      _updateState(() {
        if (profile != null) {
          _userProfile = profile;
        }
        _isLoadingProfile = false;
      });
      _onProfileLoaded();
    } catch (e) {
      debugPrint("Error fetching user profile: $e");
      if (!_isMounted()) return;
      _updateState(() {
        _isLoadingProfile = false;
      });
    }
  }
}
