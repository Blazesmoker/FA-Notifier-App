enum PendingHomeDestination { notes, notifications, none }

PendingHomeDestination pendingHomeDestinationFromPayload(String payload) {
  if (payload.startsWith('note_') ||
      payload.contains('DrawerIndex.Notes') ||
      payload == 'note_native') {
    return PendingHomeDestination.notes;
  }
  if (payload.startsWith('activity_') ||
      payload.startsWith('fa_activity_') ||
      payload.contains('DrawerIndex.Notifications') ||
      payload == 'activity_native') {
    return PendingHomeDestination.notifications;
  }
  return PendingHomeDestination.none;
}
