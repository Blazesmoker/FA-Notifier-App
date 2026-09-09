enum NotesFolder {
  inbox,
  sent,
  trash,
  archive,
}

enum NoteManagementAction {
  moveToTrash,
  moveToArchive,
  restoreFromTrash,
  restoreFromArchive,
  deletePermanently,
  markUnread,
}

class NoteManagementOutcomeUnknownException implements Exception {
  const NoteManagementOutcomeUnknownException();
}
