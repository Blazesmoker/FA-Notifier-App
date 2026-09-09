import 'package:fanotifier/features/notes/domain/message_model.dart';
import 'package:fanotifier/features/notes/domain/note_management.dart';

typedef ManagedNotesRepositoryFactory = ManagedNotesRepository Function();

abstract interface class ManagedNotesRepository {
  Future<List<Message>> fetchFolderPage({
    required NotesFolder folder,
    required int page,
  });

  Future<void> applyAction({
    required List<String> ids,
    required NotesFolder sourceFolder,
    required NoteManagementAction action,
  });
}
