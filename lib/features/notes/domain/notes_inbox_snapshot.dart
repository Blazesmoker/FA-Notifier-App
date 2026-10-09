import 'package:fanotifier/features/notes/domain/note_activity_snapshot.dart';
import 'package:fanotifier/features/notes/domain/notes_page_result.dart';

class NotesInboxSnapshot {
  const NotesInboxSnapshot({required this.page, required this.activity});

  final NotesPageResult page;
  final NoteActivitySnapshot activity;
}
