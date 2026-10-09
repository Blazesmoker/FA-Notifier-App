import 'package:fanotifier/features/notes/domain/message_model.dart';
import 'package:fanotifier/shared/fa/domain/notification_counts.dart';

class NotesPageResult {
  NotesPageResult({
    required List<Message> messages,
    required this.topbarCounts,
    this.startedAtMilliseconds,
    this.completedAtMilliseconds,
  }) : messages = List<Message>.unmodifiable(messages);

  final List<Message> messages;
  final NotificationCounts? topbarCounts;
  final int? startedAtMilliseconds;
  final int? completedAtMilliseconds;
}
