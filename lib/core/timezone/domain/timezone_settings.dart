class TimezoneSettings {
  const TimezoneSettings({
    required this.ianaName,
    required this.isDstCorrectionApplied,
  });

  final String ianaName;
  final bool isDstCorrectionApplied;
}

class CachedTimezoneSettings {
  const CachedTimezoneSettings({
    required this.settings,
    required this.lastChecked,
  });

  final TimezoneSettings settings;
  final DateTime? lastChecked;
}

enum TimezoneRemoteStatus {
  success,
  notAuthenticated,
  unavailable,
}

class TimezoneRemoteResult {
  const TimezoneRemoteResult._({
    required this.status,
    this.settings,
  });

  const TimezoneRemoteResult.success(TimezoneSettings settings)
      : this._(
          status: TimezoneRemoteStatus.success,
          settings: settings,
        );

  const TimezoneRemoteResult.notAuthenticated()
      : this._(status: TimezoneRemoteStatus.notAuthenticated);

  const TimezoneRemoteResult.unavailable()
      : this._(status: TimezoneRemoteStatus.unavailable);

  final TimezoneRemoteStatus status;
  final TimezoneSettings? settings;
}
