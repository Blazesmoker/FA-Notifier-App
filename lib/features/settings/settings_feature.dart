import 'package:FANotifier/features/settings/data/app_icon_service.dart';
import 'package:FANotifier/features/settings/data/settings_app_info_service.dart';
import 'package:FANotifier/features/settings/data/tag_blocklist_repository_impl.dart';
import 'package:FANotifier/features/settings/data/watchlist_repository_impl.dart';
import 'package:FANotifier/features/settings/domain/app_icon_repository.dart';
import 'package:FANotifier/features/settings/domain/settings_app_info_repository.dart';
import 'package:FANotifier/features/settings/domain/tag_blocklist_repository.dart';
import 'package:FANotifier/features/settings/domain/watchlist_repository.dart';

class SettingsFeature {
  const SettingsFeature._();

  static AppIconRepository createAppIconRepository() {
    return AppIconService();
  }

  static SettingsAppInfoRepository createAppInfoRepository() {
    return const SettingsAppInfoService();
  }

  static TagBlocklistRepository createTagBlocklistRepository() {
    return const TagBlocklistRepositoryImpl();
  }

  static WatchlistRepository createWatchlistRepository() {
    return const WatchlistRepositoryImpl();
  }
}
