import 'package:FANotifier/shared/fa/fa_http.dart';

class SettingsAppInfoService {
  const SettingsAppInfoService();

  String get userAgent => FAHttp.userAgent;
}
