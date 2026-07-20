import 'package:fanotifier/core/notifications/domain/local_notification_gateway.dart';
import 'package:fanotifier/features/notes/data/google_images_webview_resolver.dart';
import 'package:fanotifier/features/notes/data/new_message_service.dart';
import 'package:fanotifier/features/notes/data/note_message_service.dart';
import 'package:fanotifier/features/notes/data/note_submission_preview_repository_impl.dart';
import 'package:fanotifier/features/notes/data/note_reply_service.dart';
import 'package:fanotifier/features/notes/data/note_reply_webview_gateway_impl.dart';
import 'package:fanotifier/features/notes/data/notes_repository_impl.dart';
import 'package:fanotifier/features/notes/data/notes_refresh_service.dart';
import 'package:fanotifier/features/notes/data/notesscreen_api_service.dart';
import 'package:fanotifier/features/notes/domain/new_message_repository.dart';
import 'package:fanotifier/features/notes/domain/note_message_repository.dart';
import 'package:fanotifier/features/notes/domain/note_reply_repository.dart';
import 'package:fanotifier/features/notes/domain/note_reply_webview_gateway.dart';
import 'package:fanotifier/features/notes/domain/note_submission_preview_repository.dart';
import 'package:fanotifier/features/notes/domain/notes_refresh_port.dart';
import 'package:fanotifier/features/notes/domain/notes_repository.dart';
import 'package:fanotifier/features/notes/domain/notes_trash_repository.dart';
import 'package:fanotifier/shared/fa/domain/fa_activities_polling_port.dart';
import 'package:fanotifier/features/submissions/domain/openpost_repository.dart';

class NotesFeature {
  NotesFeature._();

  static NotesRepository createRepository({
    required NotesRefreshPort refreshPort,
    required FaActivitiesPollingPort activitiesPollingPort,
    required LocalNotificationGateway notificationGateway,
  }) {
    return NotesRepositoryImpl.create(
      refreshPort: refreshPort,
      activitiesPollingPort: activitiesPollingPort,
      notificationGateway: notificationGateway,
    );
  }

  static NewMessageRepository createNewMessageRepository() {
    return NewMessageService();
  }

  static NoteMessageRepository createNoteMessageRepository() {
    return NoteMessageService();
  }

  static NotesTrashRepository createNotesTrashRepository() {
    return NotesApiService();
  }

  static NoteReplyRepository createNoteReplyRepository() {
    return NoteReplyService();
  }

  static NoteReplyWebViewGateway createNoteReplyWebViewGateway() {
    return const NoteReplyWebViewGatewayImpl();
  }

  static NoteSubmissionPreviewRepository createSubmissionPreviewRepository({
    required OpenPostRepository openPostRepository,
  }) {
    return NoteSubmissionPreviewRepositoryImpl(
      openPostRepository: openPostRepository,
      googleImageResolver: GoogleImagesWebViewResolver(),
    );
  }

  static NotesRefreshPort get refreshPort => NotesRefreshService();
}
