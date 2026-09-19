import 'package:flutter/foundation.dart';

import 'package:fanotifier/features/journals/data/journal_api_service.dart';
import 'package:fanotifier/features/journals/domain/journal_availability_detector.dart';
import 'package:fanotifier/features/journals/domain/journal_load_result.dart';

class JournalLoadCoordinator {
  const JournalLoadCoordinator({
    required this._api,
  });

  final JournalApiService _api;

  Future<JournalLoadResult> load(String journalId) async {
    final journal = await _api.fetchJournal(journalId);

    try {
      final unavailable = looksLikeUnavailableJournal(
        title: journal.title,
        descriptionHtml: journal.submissionDescription,
        rawDate: journal.dateTimeRaw,
      );
      if (unavailable) {
        return JournalLoadResult.unavailable(journal);
      }
    } catch (e) {
      debugPrint('Error while checking for system-error markers: $e');
    }

    return JournalLoadResult.available(journal);
  }

  Future<List<Map<String, dynamic>>> fetchFallbackComments(String body) {
    return _api.fetchCommentsFromBody(body);
  }
}
