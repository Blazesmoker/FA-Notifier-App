enum JournalDeletionStatus {
  invalidDeleteLink,
  missingCookies,
  httpFailure,
  deleted,
  stillExists,
}

class JournalDeletionResult {
  const JournalDeletionResult({
    required this.status,
    this.statusCode,
  });

  final JournalDeletionStatus status;
  final int? statusCode;
}
