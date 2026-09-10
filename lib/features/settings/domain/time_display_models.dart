class TimeDisplayFormat {
  const TimeDisplayFormat({
    required this.use24HourTime,
    required this.showSeconds,
  });

  final bool use24HourTime;
  final bool showSeconds;

  TimeDisplayFormat copyWith({
    bool? use24HourTime,
    bool? showSeconds,
  }) {
    return TimeDisplayFormat(
      use24HourTime: use24HourTime ?? this.use24HourTime,
      showSeconds: showSeconds ?? this.showSeconds,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is TimeDisplayFormat &&
            other.use24HourTime == use24HourTime &&
            other.showSeconds == showSeconds;
  }

  @override
  int get hashCode => Object.hash(use24HourTime, showSeconds);
}

enum TimeDisplayOccasion {
  submissionPublication,
  submissionComment,
  journalPublication,
  journalComment,
  profileJournal,
  profileRegistration,
  profileShout,
  notificationActivity,
  notesInbox,
  notesSent,
  notesTrash,
  notesArchive,
  notePreview,
  noteDetail,
}

class TimeDisplayPreferences {
  TimeDisplayPreferences({
    required this.defaultFormat,
    required Map<TimeDisplayOccasion, bool> overrides,
  }) : overrides = Map.unmodifiable(overrides);

  final TimeDisplayFormat defaultFormat;
  final Map<TimeDisplayOccasion, bool> overrides;
}
