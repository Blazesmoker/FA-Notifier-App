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
