import 'package:fanotifier/features/journals/data/journal_action_service.dart';
import 'package:fanotifier/features/journals/data/journal_comment_service.dart';
import 'package:fanotifier/features/journals/data/journal_deletion_coordinator.dart';
import 'package:fanotifier/features/journals/data/journal_link_parser.dart';
import 'package:fanotifier/features/journals/data/journal_url_builder.dart';
import 'package:fanotifier/features/journals/data/openjournal_load_coordinator.dart';
import 'package:fanotifier/features/journals/domain/journal_deletion_result.dart';
import 'package:fanotifier/features/journals/domain/openjournal_load_result.dart';
import 'package:fanotifier/features/journals/domain/openjournal_repository.dart';

class OpenJournalRepositoryImpl implements OpenJournalRepository {
  const OpenJournalRepositoryImpl({
    required this._loadCoordinator,
    required this._actionService,
    required this._deletionCoordinator,
    required this._commentService,
  });

  final OpenJournalLoadCoordinator _loadCoordinator;
  final JournalActionService _actionService;
  final JournalDeletionCoordinator _deletionCoordinator;
  final JournalCommentService _commentService;

  @override
  Future<OpenJournalLoadResult> loadJournal(String journalId) {
    return _loadCoordinator.load(journalId);
  }

  @override
  Future<List<Map<String, dynamic>>> fetchFallbackComments(String body) {
    return _loadCoordinator.fetchFallbackComments(body);
  }

  @override
  Future<JournalDeletionResult> deleteJournal({
    required String journalId,
    required String? currentDeleteLink,
    required void Function(String deleteLink) onDeleteLinkResolved,
  }) {
    return _deletionCoordinator.delete(
      journalId: journalId,
      currentDeleteLink: currentDeleteLink,
      onDeleteLinkResolved: onDeleteLinkResolved,
    );
  }

  @override
  Future<int?> updateCommentVisibility(String link) {
    return _actionService.updateCommentVisibility(link);
  }

  @override
  Future<bool> submitComment({
    required String message,
    required String journalId,
  }) {
    return _commentService.submitComment(
      message: message,
      journalId: journalId,
    );
  }

  @override
  Future<bool> submitReplyToComment({
    required String message,
    required String journalId,
    required String commentId,
  }) {
    return _commentService.submitReplyToComment(
      message: message,
      journalId: journalId,
      commentId: commentId,
    );
  }

  @override
  String buildJournalUrl(String journalId) {
    return buildFaJournalUrl(journalId);
  }

  @override
  String resolveShortenedLink({
    required String sourceHtml,
    required String truncatedUrl,
  }) {
    return findFullShortenedJournalLink(sourceHtml, truncatedUrl) ??
        truncatedUrl;
  }

  @override
  String replaceTruncatedLinks(String htmlContent) {
    return replaceTruncatedJournalLinks(htmlContent);
  }
}
