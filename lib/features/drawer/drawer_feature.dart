import 'package:fanotifier/features/drawer/data/app_update_repository_impl.dart';
import 'package:fanotifier/features/drawer/data/nsfw_confirmation_preference.dart';
import 'package:fanotifier/features/drawer/domain/app_update_repository.dart';
import 'package:fanotifier/features/drawer/domain/nsfw_confirmation_repository.dart';

class DrawerFeature {
  const DrawerFeature._();

  static AppUpdateRepository createAppUpdateRepository() {
    return const AppUpdateRepositoryImpl();
  }

  static NsfwConfirmationRepository createNsfwConfirmationRepository() {
    return NsfwConfirmationPreference();
  }
}
