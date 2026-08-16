import 'package:flutter/foundation.dart';

import 'package:fanotifier/features/journals/data/openjournal_api_service.dart';
import 'package:fanotifier/features/journals/domain/journal_availability_detector.dart';
import 'package:fanotifier/features/journals/domain/openjournal_load_result.dart';

class OpenJournalLoadCoordinator {
  const OpenJournalLoadCoordinator({
    required this._api,
  });

  final OpenJournalApiService _api;

  Future<OpenJournalLoadResult> load(String uniqueNumber) async {
    final journal = await _api.fetchJournal(uniqueNumber);

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
    return _api.fetchCommentsFromBody(body);
  }
}
