import 'package:fanotifier/features/notes/domain/message_model.dart';

class NoteActivitySnapshot {
  const NoteActivitySnapshot({
    required this.messages,
    required this.startedAtMilliseconds,
    required this.unreadCount,
    this.fetchedPage2 = false,
    this.completedAtMilliseconds,
  });

  final List<Message> messages;
  final int startedAtMilliseconds;
  final int unreadCount;
  final bool fetchedPage2;
  final int? completedAtMilliseconds;
}
