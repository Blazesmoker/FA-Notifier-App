import 'package:fanotifier/features/settings/domain/time_display_models.dart';

abstract interface class TimeDisplayPreference {
  Future<TimeDisplayPreferences> load();

  Future<void> saveDefaultFormat(TimeDisplayFormat format);

  Future<void> saveOverrides(
    Map<TimeDisplayOccasion, bool> overrides,
  );
}
