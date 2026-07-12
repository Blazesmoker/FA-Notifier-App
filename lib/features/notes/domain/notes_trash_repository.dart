import 'package:FANotifier/features/notes/domain/message_model.dart';

typedef NotesTrashRepositoryFactory = NotesTrashRepository Function();

abstract interface class NotesTrashRepository {
  Future<List<Message>> fetchTrashPage({required int page});

  Future<void> restoreNotesFromTrash({required List<String> ids});

  Future<void> deleteNotesPermanently({required List<String> ids});
}
