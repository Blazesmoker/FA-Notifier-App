import 'package:fanotifier/features/notes/domain/message_model.dart';

bool shouldFetchSecondInboxPage({
  required List<Message> page1Messages,
  required Set<String> shownNoteIds,
  required Set<String> seenNoteIds,
  required int? topbarNotes,
}) {
  if (page1Messages.isEmpty) return false;

  final knownIds = <String>{...shownNoteIds, ...seenNoteIds};
  final allPage1RowsAreBrandNewUnread = page1Messages.every((message) {
    if (!message.isUnread) return false;
    if (message.id.trim().isEmpty) return false;
    return !knownIds.contains(message.id);
  });
  if (!allPage1RowsAreBrandNewUnread) return false;

  if (topbarNotes != null) {
    final page1UnreadCount = page1Messages.where((m) => m.isUnread).length;
    if (topbarNotes <= page1UnreadCount) return false;
  }

  return true;
}
