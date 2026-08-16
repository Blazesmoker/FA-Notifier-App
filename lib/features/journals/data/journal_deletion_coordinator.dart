import 'package:fanotifier/features/journals/data/journal_action_service.dart';
import 'package:fanotifier/features/journals/data/journal_link_parser.dart';
import 'package:fanotifier/features/journals/data/openjournal_api_service.dart';
import 'package:fanotifier/features/journals/domain/journal_deletion_result.dart';
import 'package:flutter/foundation.dart';

class JournalDeletionCoordinator {
  const JournalDeletionCoordinator({
    required this._api,
    required this._actionService,
  });

  final OpenJournalApiService _api;
  final JournalActionService _actionService;

  Future<JournalDeletionResult> delete({
    required String journalId,
    required String? currentDeleteLink,
    required void Function(String deleteLink) onDeleteLinkResolved,
  }) async {
    final deleteLink = await _resolveDeleteLink(
      journalId: journalId,
      fallback: currentDeleteLink,
      onResolved: onDeleteLinkResolved,
    );
    if (deleteLink == null ||
        !isDeleteJournalLinkForId(deleteLink, journalId)) {
      return const JournalDeletionResult(
        status: JournalDeletionStatus.invalidDeleteLink,
      );
    }

    final statusCode = await _actionService.deleteJournal(
      deleteLink: deleteLink,
      journalId: journalId,
    );
    if (statusCode == null) {
      return const JournalDeletionResult(
        status: JournalDeletionStatus.missingCookies,
      );
    }
    if (statusCode < 200 || statusCode >= 400) {
      return JournalDeletionResult(
        status: JournalDeletionStatus.httpFailure,
        statusCode: statusCode,
      );
    }

    if (await _api.isJournalDeleted(journalId)) {
      return const JournalDeletionResult(
        status: JournalDeletionStatus.deleted,
      );
    }

    await _resolveDeleteLink(
      journalId: journalId,
      fallback: currentDeleteLink,
      onResolved: onDeleteLinkResolved,
    );
    return const JournalDeletionResult(
      status: JournalDeletionStatus.stillExists,
    );
  }

  Future<String?> _resolveDeleteLink({
    required String journalId,
    required String? fallback,
    required void Function(String deleteLink) onResolved,
  }) async {
    try {
      final fetched = await _api.fetchDeleteLinkFromControls(journalId);
      if (fetched != null && fetched.trim().isNotEmpty) {
        onResolved(fetched);
        return fetched;
      }
    } catch (e) {
      debugPrint('Failed to fetch delete link: $e');
    }
    return fallback;
  }
}
