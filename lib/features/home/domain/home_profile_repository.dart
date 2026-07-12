import 'package:FANotifier/shared/fa/domain/user_profile.dart';

abstract interface class HomeProfileRepository {
  Future<UserProfile?> fetchUserProfile({String? homeHtml});
}
