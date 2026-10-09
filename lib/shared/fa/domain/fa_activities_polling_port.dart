import 'package:fanotifier/features/notes/domain/note_activity_snapshot.dart';
import 'package:fanotifier/features/notes/domain/notes_repository.dart';
import 'package:fanotifier/shared/fa/domain/fa_notification_state_port.dart';
import 'package:fanotifier/shared/fa/domain/notification_counts.dart';

abstract interface class FaActivitiesPollingPort {
  void start({
    required FaNotificationStatePort faNotificationService,
    required NotesRepositoryFactory notesRepositoryFactory,
  });

  Future<void> ensureNotificationsFresh({required String source});

  void stop();

  void resetSchedule();

  void setNotesScreenVisible(bool visible);

  void setSubmissionsScreenVisible(bool visible);

  void setNotificationsScreenVisible(
    bool visible, {
    String? activeSectionTitle,
  });

  void setNotificationsScreenActiveSection(String? sectionTitle);

  Future<void> triggerNow({
    required bool resetTimer,
    required String source,
    bool requireFresh = false,
  });

  Future<void> handleExternalCounts({
    required NotificationCounts currentCounts,
    required bool resetTimer,
    required String source,
    NoteActivitySnapshot? noteActivitySnapshot,
    int? startedAtMilliseconds,
  });
}
