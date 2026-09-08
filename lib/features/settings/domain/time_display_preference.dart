abstract interface class TimeDisplayPreference {
  Future<bool> loadUse24HourTime();

  Future<void> saveUse24HourTime(bool value);
}
