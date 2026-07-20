import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fanotifier/features/settings/domain/app_icon_repository.dart';

class AppIconService implements AppIconRepository {
  static const _platform = MethodChannel('com.blazesmoker.fanotifier/icon');
  static const _useAdaptiveIconKey = 'useAdaptiveIcon';

  @override
  Future<bool> loadUseAdaptiveIcon() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_useAdaptiveIconKey) ?? false;
  }

  @override
  Future<void> setUseAdaptiveIcon(bool useAdaptiveIcon) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_useAdaptiveIconKey, useAdaptiveIcon);
    await _platform.invokeMethod('switchIcon', {'useAdaptive': useAdaptiveIcon});
  }
}
