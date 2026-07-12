import 'package:flutter/foundation.dart';

import 'package:FANotifier/core/timezone/domain/timezone_repository.dart';
import 'package:FANotifier/core/timezone/domain/timezone_settings.dart';

class TimezoneProvider with ChangeNotifier {
  TimezoneProvider({required TimezoneRepository repository})
      : _repository = repository;

  static const Duration _refreshInterval = Duration(days: 14);
  final TimezoneRepository _repository;
  String _userTimezoneIanaName = 'Etc/UTC';
  bool _isDstCorrectionApplied = false;

  String get userTimezoneIanaName => _userTimezoneIanaName;
  bool get isDstCorrectionApplied => _isDstCorrectionApplied;

  Future<void> fetchTimezone() async {
    final now = DateTime.now();
    final cached = await _repository.loadCached();
    if (cached != null) {
      _apply(cached.settings);
      notifyListeners();
      final lastChecked = cached.lastChecked;
      if (lastChecked != null &&
          now.difference(lastChecked) < _refreshInterval) {
        return;
      }
    }

    final remote = await _repository.fetchRemote();
    if (remote.status == TimezoneRemoteStatus.notAuthenticated) {
      if (cached == null) {
        _apply(
          const TimezoneSettings(
            ianaName: 'Etc/UTC',
            isDstCorrectionApplied: false,
          ),
        );
        notifyListeners();
      }
      return;
    }

    final remoteSettings = remote.settings;
    if (remoteSettings != null) {
      _apply(remoteSettings);
      await _repository.save(remoteSettings, now);
    } else if (cached == null) {
      _apply(
        const TimezoneSettings(
          ianaName: 'Etc/UTC',
          isDstCorrectionApplied: false,
        ),
      );
    }
    notifyListeners();
  }

  void _apply(TimezoneSettings settings) {
    _userTimezoneIanaName = settings.ianaName;
    _isDstCorrectionApplied = settings.isDstCorrectionApplied;
  }
}
