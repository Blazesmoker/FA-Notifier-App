import 'package:fanotifier/shared/fa/domain/notification_counts.dart';

const String appUpdateNotificationPayload = 'app_update_available';

const List<String> notificationTypes = <String>[
  'submissions',
  'watches',
  'comments',
  'favorites',
  'journals',
  'notes',
  'activities',
  'updates',
];

bool isActivityNotificationPayload(String payload) {
  return payload.startsWith('fa_activity_') ||
      payload.startsWith('activity_') ||
      payload.contains('DrawerIndex.Notifications') ||
      payload == 'activity_native';
}

bool isNoteNotificationPayload(String payload) {
  return payload.startsWith('note_') ||
      payload.contains('DrawerIndex.Notes') ||
      payload == 'note_native';
}

String? noteIdFromNotificationPayload(String payload) {
  const prefix = 'note_';
  if (!payload.startsWith(prefix)) return null;
  final noteId = payload.substring(prefix.length).trim();
  return noteId.isEmpty ? null : noteId;
}

String activityPayloadWithCounts(String payload, NotificationCounts counts) {
  return '$payload|activityCounts=${counts.submissions},${counts.watches},'
      '${counts.comments},${counts.favorites},${counts.journals},${counts.notes}';
}

NotificationCounts? activityCountsFromPayload(String payload) {
  if (!isActivityNotificationPayload(payload)) return null;
  final parts = payload.split('|activityCounts=');
  if (parts.length != 2) return null;
  final values = parts.last.split(',').map(int.tryParse).toList();
  if (values.length != 6 || values.any((value) => value == null || value < 0)) {
    return null;
  }
  return NotificationCounts(
    submissions: values[0]!,
    watches: values[1]!,
    comments: values[2]!,
    favorites: values[3]!,
    journals: values[4]!,
    notes: values[5]!,
  );
}
