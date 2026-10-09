import 'package:fanotifier/shared/fa/domain/notification_counts.dart';

class FaPageCounterObservation {
  const FaPageCounterObservation({
    required this.counts,
    required this.startedAtMilliseconds,
    required this.sessionGeneration,
  });

  final NotificationCounts counts;
  final int startedAtMilliseconds;
  final int sessionGeneration;
}
