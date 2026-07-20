import 'package:fanotifier/features/journals/domain/openjournal_fetch_result.dart';

enum OpenJournalLoadStatus {
  available,
  unavailable,
}

class OpenJournalLoadResult {
  const OpenJournalLoadResult._({
    required this.status,
    required this.journal,
  });

  const OpenJournalLoadResult.available(OpenJournalFetchResult journal)
      : this._(
          status: OpenJournalLoadStatus.available,
          journal: journal,
        );

  const OpenJournalLoadResult.unavailable(OpenJournalFetchResult journal)
      : this._(
          status: OpenJournalLoadStatus.unavailable,
          journal: journal,
        );

  final OpenJournalLoadStatus status;
  final OpenJournalFetchResult journal;

  bool get isUnavailable => status == OpenJournalLoadStatus.unavailable;

  bool get shouldFetchFallbackComments =>
      status == OpenJournalLoadStatus.available &&
      journal.commentBodies.isEmpty &&
      journal.submissionDescription != null;
}
