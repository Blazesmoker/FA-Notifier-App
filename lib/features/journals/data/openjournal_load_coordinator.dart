import 'package:flutter/foundation.dart';

import 'package:FANotifier/features/journals/domain/journal_availability_detector.dart';
import 'package:FANotifier/features/journals/domain/openjournal_load_result.dart';
import 'package:FANotifier/features/journals/domain/openjournal_repository.dart';

class OpenJournalLoadCoordinator {
  const OpenJournalLoadCoordinator({
    required OpenJournalRepository repository,
  }) : _repository = repository;

  final OpenJournalRepository _repository;

  Future<OpenJournalLoadResult> load(String uniqueNumber) async {
    final journal = await _repository.fetchJournal(uniqueNumber);

    try {
      final unavailable = looksLikeUnavailableJournal(
        title: journal.title,
        descriptionHtml: journal.submissionDescription,
        rawDate: journal.dateTimeRaw,
      );
      if (unavailable) {
        return OpenJournalLoadResult.unavailable(journal);
      }
    } catch (e) {
      debugPrint('Error while checking for system-error markers: $e');
    }

    return OpenJournalLoadResult.available(journal);
  }

  Future<List<Map<String, dynamic>>> fetchFallbackComments(String body) {
    return _repository.fetchCommentsFromBody(body);
  }
}
