import 'package:FANotifier/features/journals/data/create_journal_repository_impl.dart';
import 'package:FANotifier/features/journals/data/journal_action_service.dart';
import 'package:FANotifier/features/journals/data/journal_comment_service.dart';
import 'package:FANotifier/features/journals/data/journal_deletion_coordinator.dart';
import 'package:FANotifier/features/journals/data/openjournal_api_service.dart';
import 'package:FANotifier/features/journals/data/openjournal_load_coordinator.dart';
import 'package:FANotifier/features/journals/data/openjournal_repository_impl.dart';
import 'package:FANotifier/features/journals/domain/create_journal_repository.dart';
import 'package:FANotifier/features/journals/domain/openjournal_repository.dart';

class JournalsFeature {
  const JournalsFeature._();

  static OpenJournalRepository createOpenJournalRepository() {
    final api = OpenJournalApiService();
    const actionService = JournalActionService();
    return OpenJournalRepositoryImpl(
      loadCoordinator: OpenJournalLoadCoordinator(api: api),
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
