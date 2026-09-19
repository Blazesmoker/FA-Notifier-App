import 'package:fanotifier/features/journals/domain/journal_fetch_result.dart';

enum JournalLoadStatus {
  available,
  unavailable,
}

class JournalLoadResult {
  const JournalLoadResult._({
    required this.status,
    required this.journal,
  });

  const JournalLoadResult.available(JournalFetchResult journal)
      : this._(
          status: JournalLoadStatus.available,
          journal: journal,
        );

  const JournalLoadResult.unavailable(JournalFetchResult journal)
      : this._(
          status: JournalLoadStatus.unavailable,
          journal: journal,
        );

  final JournalLoadStatus status;
  final JournalFetchResult journal;

  bool get isUnavailable => status == JournalLoadStatus.unavailable;

  bool get shouldFetchFallbackComments =>
      status == JournalLoadStatus.available &&
      journal.commentBodies.isEmpty &&
      journal.submissionDescription != null;
}
