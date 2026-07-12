import 'package:FANotifier/features/drawer/domain/app_update_info.dart';

abstract interface class AppUpdateRepository {
  Future<AppUpdateInfo?> fetchLatest({bool forceRefresh = false});

  Future<bool?> isCurrentVersionAllowed();
}
