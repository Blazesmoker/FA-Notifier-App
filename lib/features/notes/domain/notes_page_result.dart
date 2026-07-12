import 'package:FANotifier/features/notes/domain/message_model.dart';
import 'package:FANotifier/features/notifications/domain/notification_counts.dart';

class NotesPageResult {
  NotesPageResult({
    required List<Message> messages,
    required this.topbarCounts,
  }) : messages = List<Message>.unmodifiable(messages);

  final List<Message> messages;
  final NotificationCounts? topbarCounts;
}
