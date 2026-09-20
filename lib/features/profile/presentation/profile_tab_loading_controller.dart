import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:fanotifier/features/profile/domain/profile_section.dart';

class ProfileTabLoadingController {
  ProfileTabLoadingController({
    required this._isMounted,
    required this._currentIndex,
    required this._updateState,
  });

  final bool Function() _isMounted;
  final int Function() _currentIndex;
  final void Function(VoidCallback) _updateState;
  static const Duration _tabSettleDelay = Duration(milliseconds: 100);
  Timer? _tabSettleTimer;
  final Set<ProfileSection> _lazyLoadedSections = <ProfileSection>{};

  bool isLoaded(ProfileSection section) => _lazyLoadedSections.contains(section);

  void loadInitialSection(ProfileSection section) {
    _lazyLoadedSections.add(section);
  }

  void cancelPendingLoad() {
    _tabSettleTimer?.cancel();
  }

  void dispose() {
    cancelPendingLoad();
  }

  void scheduleLoad(int index) {
    _tabSettleTimer?.cancel();
    _tabSettleTimer = Timer(_tabSettleDelay, () {
      if (!_isMounted()) return;
      if (_currentIndex() != index) return;
      final section = ProfileSection.values[index];
      if (_lazyLoadedSections.contains(section)) return;
      _updateState(() {
        _lazyLoadedSections.add(section);
      });
    });
  }
}
