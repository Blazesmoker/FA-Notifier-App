enum NotificationExecutionContext {
  backgroundPeriodic('background_periodic'),
  foregroundPeriodic('foreground_periodic'),
  foregroundResume('foreground_resume'),
  foregroundImmediate('foreground_immediate');

  const NotificationExecutionContext(this.analyticsValue);

  final String analyticsValue;
}

enum NotificationCheckOutcome {
  contentFound('content_found'),
  empty('empty'),
  skippedAppActive('skipped_app_active'),
  failed('failed'),
  cancelled('cancelled'),
  timedOut('timed_out');

  const NotificationCheckOutcome(this.analyticsValue);

  final String analyticsValue;
}

