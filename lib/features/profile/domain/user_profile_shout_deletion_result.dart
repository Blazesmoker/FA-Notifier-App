enum UserProfileShoutDeletionStatus {
  unmatched,
  success,
  missingCookies,
  partialFailure,
  failure,
}

class UserProfileShoutDeletionResult {
  const UserProfileShoutDeletionResult({
    required this.status,
    this.error,
  });

  final UserProfileShoutDeletionStatus status;
  final Object? error;
}
