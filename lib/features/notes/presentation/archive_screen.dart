import 'package:material_ui/material_ui.dart';
import 'package:fanotifier/features/notes/domain/note_management.dart';
import 'package:fanotifier/features/notes/presentation/managed_notes_folder_screen.dart';

class ArchiveScreen extends StatelessWidget {
  const ArchiveScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ManagedNotesFolderScreen(folder: NotesFolder.archive);
  }
}
