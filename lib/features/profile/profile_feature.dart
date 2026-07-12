import 'package:provider/provider.dart';

import 'package:FANotifier/features/profile/data/image_inspect_media_export_service.dart';
import 'package:FANotifier/features/profile/data/profile_favorites_service.dart';
import 'package:FANotifier/features/profile/data/profile_gallery_service.dart';
import 'package:FANotifier/features/profile/data/profile_gallery_favorite_repository_impl.dart';
import 'package:FANotifier/features/profile/data/profile_journals_service.dart';
import 'package:FANotifier/features/profile/data/profile_scraps_service.dart';
import 'package:FANotifier/features/profile/data/shout_service.dart';
import 'package:FANotifier/features/profile/data/shout_text_parser.dart';
import 'package:FANotifier/features/profile/data/user_description_service.dart';
import 'package:FANotifier/features/profile/data/user_profile_repository_impl.dart';
import 'package:FANotifier/features/profile/domain/profile_favorites_repository.dart';
import 'package:FANotifier/features/profile/domain/profile_gallery_repository.dart';
import 'package:FANotifier/features/profile/domain/profile_gallery_favorite_repository.dart';
import 'package:FANotifier/features/profile/domain/profile_journals_repository.dart';
import 'package:FANotifier/features/profile/domain/profile_media_export_repository.dart';
import 'package:FANotifier/features/profile/domain/profile_scraps_repository.dart';
import 'package:FANotifier/features/profile/domain/profile_shout_repository.dart';
import 'package:FANotifier/features/profile/domain/profile_shout_text_repository.dart';
import 'package:FANotifier/features/profile/domain/user_description_repository.dart';
import 'package:FANotifier/features/profile/domain/user_profile_repository.dart';

class ProfileFeature {
  ProfileFeature._();

  static Provider<UserProfileRepository> repositoryProvider() {
    return Provider<UserProfileRepository>(
      create: (_) => UserProfileRepositoryImpl(),
    );
  }

  static ProfileShoutRepository createShoutRepository() {
    return ShoutService();
  }

  static ProfileScrapsRepository createScrapsRepository() {
    return ProfileScrapsService();
  }

  static ProfileFavoritesRepository createFavoritesRepository() {
    return ProfileFavoritesService();
  }

  static ProfileGalleryRepository createGalleryRepository() {
    return ProfileGalleryService();
  }

  static ProfileGalleryFavoriteRepository createGalleryFavoriteRepository() {
    return ProfileGalleryFavoriteRepositoryImpl();
  }

  static ProfileJournalsRepository createJournalsRepository() {
    return ProfileJournalsService();
  }

  static ProfileMediaExportRepository createMediaExportRepository() {
    return const ImageInspectMediaExportService();
  }

  static UserDescriptionRepository createUserDescriptionRepository() {
    return UserDescriptionService();
  }

  static ProfileShoutTextRepository createShoutTextRepository() {
    return const ShoutTextParser();
  }
}
