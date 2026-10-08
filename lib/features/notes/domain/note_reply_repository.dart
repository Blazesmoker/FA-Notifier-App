import 'package:fanotifier/features/notes/domain/note_reply_models.dart';

typedef NoteReplyRepositoryFactory = NoteReplyRepository Function();

abstract interface class NoteReplyRepository {
  Future<NoteReplyContext> fetchReplyContext(
    String messageLink, {
    required String folder,
  });

  Future<NoteReplySendResult> sendModernReply({
    required String messageLink,
    required String folder,
    required NoteReplyContext replyContext,
    required String recipient,
    required String subject,
    required String replyText,
    required String originalContent,
  });

  void close();
}
