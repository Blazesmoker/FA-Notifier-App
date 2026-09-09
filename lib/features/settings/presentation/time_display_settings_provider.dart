import 'package:fanotifier/features/settings/domain/time_display_models.dart';
import 'package:fanotifier/features/settings/domain/time_display_preference.dart';
import 'package:flutter/foundation.dart';

class TimeDisplaySettingsProvider with ChangeNotifier {
  TimeDisplaySettingsProvider({
    required TimeDisplayPreference preference,
  }) : _preference = preference {
    _load();
  }

  final TimeDisplayPreference _preference;
  TimeDisplayFormat _defaultFormat = const TimeDisplayFormat(
    use24HourTime: false,
    showSeconds: true,
  );
  Map<TimeDisplayOccasion, TimeDisplayFormat> _overrides = {};

  TimeDisplayFormat get defaultFormat => _defaultFormat;

  TimeDisplayFormat formatFor(TimeDisplayOccasion occasion) {
    return _overrides[occasion] ?? _defaultFormat;
  }

  bool usesDefaultFormat(TimeDisplayOccasion occasion) {
    return !_overrides.containsKey(occasion);
  }

  Future<void> _load() async {
    final preferences = await _preference.load();
    _defaultFormat = preferences.defaultFormat;
    _overrides = Map.of(preferences.overrides);
    notifyListeners();
  }

  Future<void> setUse24HourTime(bool value) async {
    final next = _defaultFormat.copyWith(use24HourTime: value);
    if (_defaultFormat == next) return;
    _defaultFormat = next;
    notifyListeners();
    await _preference.saveDefaultFormat(next);
  }

  Future<void> setShowSeconds(bool value) async {
    final next = _defaultFormat.copyWith(showSeconds: value);
    if (_defaultFormat == next) return;
    _defaultFormat = next;
    notifyListeners();
    await _preference.saveDefaultFormat(next);
  }

  Future<void> setUsesDefaultFormat(
    TimeDisplayOccasion occasion,
    bool value,
  ) async {
    if (value) {
      if (_overrides.remove(occasion) == null) return;
    } else {
      if (_overrides.containsKey(occasion)) return;
      _overrides[occasion] = _defaultFormat;
    }
    notifyListeners();
    await _preference.saveOverrides(Map.of(_overrides));
  }

  Future<void> setOccasionUse24HourTime(
    TimeDisplayOccasion occasion,
    bool value,
  ) async {
    await _setOccasionFormat(
      occasion,
      formatFor(occasion).copyWith(use24HourTime: value),
    );
  }

  Future<void> setOccasionShowSeconds(
    TimeDisplayOccasion occasion,
    bool value,
  ) async {
    await _setOccasionFormat(
      occasion,
      formatFor(occasion).copyWith(showSeconds: value),
    );
  }

  Future<void> _setOccasionFormat(
    TimeDisplayOccasion occasion,
    TimeDisplayFormat format,
  ) async {
    if (_overrides[occasion] == format) return;
    _overrides[occasion] = format;
    notifyListeners();
    await _preference.saveOverrides(Map.of(_overrides));
  }
}
