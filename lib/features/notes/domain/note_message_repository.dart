import 'package:fanotifier/features/notes/domain/note_message_models.dart';

typedef NoteMessageRepositoryFactory = NoteMessageRepository Function();

abstract interface class NoteMessageRepository {
  Future<NoteMessageFetchResult> fetchMessageDetails({
    required String messageLink,
    required String folder,
    bool closeConnection = false,
  });

  Future<int?> markAsUnread({
    required String folder,
    required String messageId,
    required int pageNumber,
  });

  void close();
}
