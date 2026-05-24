import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppIconService {
  static const _platform = MethodChannel('com.blazesmoker.fanotifier/icon');
  static const _useAdaptiveIconKey = 'useAdaptiveIcon';

  Future<bool> loadUseAdaptiveIcon() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_useAdaptiveIconKey) ?? false;
  }

  Future<void> setUseAdaptiveIcon(bool useAdaptiveIcon) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_useAdaptiveIconKey, useAdaptiveIcon);
    await _platform.invokeMethod('switchIcon', {'useAdaptive': useAdaptiveIcon});
  }
}
