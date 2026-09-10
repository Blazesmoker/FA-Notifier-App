import 'package:fanotifier/features/settings/domain/time_display_models.dart';
import 'package:fanotifier/features/settings/domain/time_display_preference.dart';
import 'package:flutter/foundation.dart';

class TimeDisplaySettingsProvider with ChangeNotifier {
  TimeDisplaySettingsProvider({
    required TimeDisplayPreference preference,
  }) : _preference = preference {
    _loadFuture = _load();
  }

  static const TimeDisplayFormat _initialFormat = TimeDisplayFormat(
    use24HourTime: false,
    showSeconds: true,
  );

  final TimeDisplayPreference _preference;
  late final Future<void> _loadFuture;
  TimeDisplayFormat _defaultFormat = _initialFormat;
  Map<TimeDisplayOccasion, bool> _overrides = {};

  TimeDisplayFormat get defaultFormat => _defaultFormat;

  TimeDisplayFormat formatFor(TimeDisplayOccasion occasion) {
    return TimeDisplayFormat(
      use24HourTime: _defaultFormat.use24HourTime,
      showSeconds: _overrides[occasion] ?? _defaultFormat.showSeconds,
    );
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

  Future<void> setOccasionShowSeconds(
    TimeDisplayOccasion occasion,
    bool value,
  ) async {
    final previous = _overrides[occasion];
    if (value == _defaultFormat.showSeconds) {
      if (_overrides.remove(occasion) == null) return;
    } else {
      if (previous == value) return;
      _overrides[occasion] = value;
    }
    notifyListeners();
    await _preference.saveOverrides(Map.of(_overrides));
  }

  Future<void> resetSettings() async {
    await _loadFuture;
    if (_defaultFormat == _initialFormat && _overrides.isEmpty) return;
    _defaultFormat = _initialFormat;
    _overrides = {};
    notifyListeners();
    await Future.wait([
      _preference.saveDefaultFormat(_initialFormat),
      _preference.saveOverrides(const {}),
    ]);
  }
}
