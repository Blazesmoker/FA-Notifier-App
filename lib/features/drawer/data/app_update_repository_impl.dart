import 'package:fanotifier/features/drawer/data/app_update_service.dart';
import 'package:fanotifier/features/drawer/domain/app_update_repository.dart';

class AppUpdateRepositoryImpl implements AppUpdateRepository {
  const AppUpdateRepositoryImpl();

  @override
  Future<AppUpdateInfo?> fetchLatest({bool forceRefresh = false}) {
    return fetchLatestAppUpdateInfo(forceRefresh: forceRefresh);
  }

  @override
  Future<bool?> isCurrentVersionAllowed() {
    return isCurrentAppVersionAllowed();
  }
}
