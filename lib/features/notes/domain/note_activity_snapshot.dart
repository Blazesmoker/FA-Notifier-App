import 'package:fanotifier/features/notes/domain/message_model.dart';

class NoteActivitySnapshot {
  const NoteActivitySnapshot({
    required this.messages,
    required this.startedAtMilliseconds,
    required this.unreadCount,
  });

  final List<Message> messages;
  final int startedAtMilliseconds;
  final int unreadCount;
}
