import 'package:fanotifier/features/home/data/home_fa_service.dart';
import 'package:fanotifier/features/home/domain/home_profile_repository.dart';
import 'package:fanotifier/shared/fa/domain/user_profile.dart';

class HomeProfileRepositoryImpl implements HomeProfileRepository {
  HomeProfileRepositoryImpl({FaService? faService})
      : _faService = faService ?? FaService();

  final FaService _faService;

  @override
  Future<UserProfile?> fetchUserProfile({String? homeHtml}) {
    return _faService.fetchUserProfile(homeHtml: homeHtml);
  }
}
