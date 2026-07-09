import 'package:shared_preferences/shared_preferences.dart';

class HomeLoginWebViewLoadThrottle {
  const HomeLoginWebViewLoadThrottle();

  static const String _lastLoadAtMsKey = 'login_webview.last_load_at_ms';
  static const Duration _minSpacing = Duration(seconds: 1);

  Future<HomeLoginWebViewLoadSlot> waitForAvailableSlot() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.reload();
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final lastLoadMs = preferences.getInt(_lastLoadAtMsKey) ?? 0;
    final waitMs = _minSpacing.inMilliseconds - (nowMs - lastLoadMs);
    if (waitMs > 0) {
      await Future<void>.delayed(Duration(milliseconds: waitMs));
    }
    return HomeLoginWebViewLoadSlot._(preferences);
  }
}

class HomeLoginWebViewLoadSlot {
  const HomeLoginWebViewLoadSlot._(this._preferences);

  final SharedPreferences _preferences;

  Future<void> recordLoadStart() async {
    await _preferences.setInt(
      HomeLoginWebViewLoadThrottle._lastLoadAtMsKey,
      DateTime.now().millisecondsSinceEpoch,
    );
  }
}
