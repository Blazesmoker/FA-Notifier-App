import 'package:fanotifier/shared/fa/domain/user_profile.dart';

abstract interface class HomeProfileRepository {
  Future<UserProfile?> fetchUserProfile({String? homeHtml});
}
