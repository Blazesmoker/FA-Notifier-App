import 'package:fanotifier/core/timezone/domain/timezone_settings.dart';

abstract class TimezoneRepository {
  Future<CachedTimezoneSettings?> loadCached();

  Future<TimezoneRemoteResult> fetchRemote();

  Future<void> save(TimezoneSettings settings, DateTime checkedAt);
}
