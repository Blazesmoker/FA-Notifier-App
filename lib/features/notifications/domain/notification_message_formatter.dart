import 'package:FANotifier/features/notifications/domain/notification_counts.dart';

String _formatNotificationPart({
  required int current,
  required int increasedBy,
  required String suffix,
}) {
  if (current <= 0) return '';
  if (increasedBy > 0) {
    return '$current$suffix(+$increasedBy)';
  }
  return '$current$suffix';
}

String buildNotificationMessage(
  NotificationCounts counts,
  NotificationCounts increases,
) {
  final parts = <String>[];
  final submissions = _formatNotificationPart(
    current: counts.submissions,
    increasedBy: increases.submissions,
    suffix: 'S',
  );
  if (submissions.isNotEmpty) parts.add(submissions);
  final watches = _formatNotificationPart(
    current: counts.watches,
    increasedBy: increases.watches,
    suffix: 'W',
  );
  if (watches.isNotEmpty) parts.add(watches);
  final comments = _formatNotificationPart(
    current: counts.comments,
    increasedBy: increases.comments,
    suffix: 'C',
  );
  if (comments.isNotEmpty) parts.add(comments);
  final favorites = _formatNotificationPart(
    current: counts.favorites,
    increasedBy: increases.favorites,
    suffix: 'F',
  );
  if (favorites.isNotEmpty) parts.add(favorites);
  final journals = _formatNotificationPart(
    current: counts.journals,
    increasedBy: increases.journals,
    suffix: 'J',
  );
  if (journals.isNotEmpty) parts.add(journals);
  final notes = _formatNotificationPart(
    current: counts.notes,
    increasedBy: increases.notes,
    suffix: 'N',
  );
  if (notes.isNotEmpty) parts.add(notes);
  return parts.join(' | ');
}
