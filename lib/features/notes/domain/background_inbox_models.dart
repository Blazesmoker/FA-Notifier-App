import 'package:FANotifier/features/notes/domain/message_model.dart';
import 'package:FANotifier/features/notifications/domain/notification_counts.dart';

class BackgroundInboxSnapshot {
  const BackgroundInboxSnapshot({
    required this.messages,
    required this.topbarCounts,
    required this.fetchedPage2,
  });

  final List<Message> messages;
  final NotificationCounts? topbarCounts;
  final bool fetchedPage2;
}

class BackgroundInboxPage {
  const BackgroundInboxPage({
    required this.messages,
    required this.topbarCounts,
  });

  final List<Message> messages;
  final NotificationCounts? topbarCounts;
}
