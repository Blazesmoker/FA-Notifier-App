import 'package:fanotifier/features/journals/data/create_journal_repository_impl.dart';
import 'package:fanotifier/features/journals/data/journal_action_service.dart';
import 'package:fanotifier/features/journals/data/journal_comment_service.dart';
import 'package:fanotifier/features/journals/data/journal_deletion_coordinator.dart';
import 'package:fanotifier/features/journals/data/journal_api_service.dart';
import 'package:fanotifier/features/journals/data/journal_load_coordinator.dart';
import 'package:fanotifier/features/journals/data/journal_details_repository_impl.dart';
import 'package:fanotifier/features/journals/domain/create_journal_repository.dart';
import 'package:fanotifier/features/journals/domain/journal_details_repository.dart';

class JournalsFeature {
  const JournalsFeature._();

  static JournalDetailsRepository createJournalDetailsRepository() {
    final api = JournalApiService();
    const actionService = JournalActionService();
    return JournalDetailsRepositoryImpl(
      loadCoordinator: JournalLoadCoordinator(api: api),
      actionService: actionService,
      deletionCoordinator: JournalDeletionCoordinator(
        api: api,
        actionService: actionService,
      ),
      commentService: JournalCommentService(),
    );
  }

  static CreateJournalRepository createCreateJournalRepository() {
    return const CreateJournalRepositoryImpl();
  }
}
