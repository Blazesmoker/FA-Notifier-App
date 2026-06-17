// lib/model/user_profile.dart

class UserProfile {
  final String username;
  final String profileImageUrl;
  final String? profileUrl;

  UserProfile({
    required this.username,
    required this.profileImageUrl,
    this.profileUrl,
  });
}

String? userProfileRouteNickname(UserProfile profile) {
  final profileUrl = profile.profileUrl;
  if (profileUrl != null && profileUrl.isNotEmpty) {
    final uri = Uri.tryParse(profileUrl);
    final segments = uri?.pathSegments ?? const <String>[];
    final userIndex = segments.indexWhere((s) => s.toLowerCase() == 'user');
    if (userIndex >= 0 && userIndex + 1 < segments.length) {
      final nickname = segments[userIndex + 1].trim();
      if (nickname.isNotEmpty) return nickname.toLowerCase();
    }
  }

  final username = profile.username.trim();
  if (username.isNotEmpty && username != 'Username') {
    return username.toLowerCase();
  }

  final imageUrl = profile.profileImageUrl;
  if (imageUrl.isEmpty) return null;
  final filename = imageUrl.split('/').last;
  final nickname = filename.contains('.')
      ? filename.substring(0, filename.lastIndexOf('.'))
      : filename;
  final trimmed = nickname.trim();
  return trimmed.isEmpty ? null : trimmed.toLowerCase();
}
