import 'package:FANotifier/core/network/fa_http.dart';
import 'package:FANotifier/features/settings/domain/settings_app_info_repository.dart';

class SettingsAppInfoService implements SettingsAppInfoRepository {
  const SettingsAppInfoService();

  @override
  String get userAgent => FAHttp.userAgent;
}
