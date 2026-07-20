import 'package:fanotifier/features/journals/domain/journal_deletion_result.dart';
import 'package:fanotifier/features/journals/domain/openjournal_load_result.dart';

abstract class OpenJournalRepository {
  Future<OpenJournalLoadResult> loadJournal(String journalId);

  Future<List<Map<String, dynamic>>> fetchFallbackComments(String body);

  Future<JournalDeletionResult> deleteJournal({
    required String journalId,
    required String? currentDeleteLink,
    required void Function(String deleteLink) onDeleteLinkResolved,
  });

  Future<int?> updateCommentVisibility(String link);

  Future<bool> submitComment({
    required String message,
    required String journalId,
  });

  Future<bool> submitReplyToComment({
    required String message,
    required String journalId,
    required String commentId,
  });

  String buildJournalUrl(String journalId);

  String resolveShortenedLink({
    required String sourceHtml,
    required String truncatedUrl,
  });

  String replaceTruncatedLinks(String htmlContent);
}
