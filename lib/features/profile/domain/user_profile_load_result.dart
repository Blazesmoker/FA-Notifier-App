import 'package:fanotifier/features/profile/domain/user_profile_api_models.dart';

class UserProfileLoadResult {
  const UserProfileLoadResult({
    required this.sanitizedUsername,
    required this.parsed,
    required this.shouldShowDescription,
  });

  final String sanitizedUsername;
  final UserProfileParsed parsed;
  final bool shouldShowDescription;
}
