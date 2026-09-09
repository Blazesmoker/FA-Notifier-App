import 'dart:convert';

import 'package:fanotifier/features/settings/domain/time_display_models.dart';
import 'package:fanotifier/features/settings/domain/time_display_preference.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TimeDisplayPreferenceImpl implements TimeDisplayPreference {
  const TimeDisplayPreferenceImpl();

  static const String _use24HourTimeKey = 'time_display_use_24_hour';
  static const String _showSecondsKey = 'time_display_show_seconds';
  static const String _overridesKey = 'time_display_overrides_v1';

  @override
  Future<TimeDisplayPreferences> load() async {
    final preferences = await SharedPreferences.getInstance();
    final defaultFormat = TimeDisplayFormat(
      use24HourTime: preferences.getBool(_use24HourTimeKey) ?? false,
      showSeconds: preferences.getBool(_showSecondsKey) ?? true,
    );
    final overrides = <TimeDisplayOccasion, TimeDisplayFormat>{};
    final encodedOverrides = preferences.getString(_overridesKey);
    if (encodedOverrides != null) {
      try {
        final decoded = jsonDecode(encodedOverrides);
        if (decoded is Map<String, dynamic>) {
          for (final entry in decoded.entries) {
            final occasion = _occasionFromId(entry.key);
            final value = entry.value;
            if (occasion == null || value is! Map<String, dynamic>) continue;
            final use24HourTime = value['use24HourTime'];
            final showSeconds = value['showSeconds'];
            if (use24HourTime is bool && showSeconds is bool) {
              overrides[occasion] = TimeDisplayFormat(
                use24HourTime: use24HourTime,
                showSeconds: showSeconds,
              );
            }
          }
        }
      } on FormatException {
        overrides.clear();
      }
    }
    return TimeDisplayPreferences(
      defaultFormat: defaultFormat,
      overrides: overrides,
    );
  }

  @override
  Future<void> saveDefaultFormat(TimeDisplayFormat format) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(
      _use24HourTimeKey,
      format.use24HourTime,
    );
    await preferences.setBool(_showSecondsKey, format.showSeconds);
  }

  @override
  Future<void> saveOverrides(
    Map<TimeDisplayOccasion, TimeDisplayFormat> overrides,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = <String, Map<String, bool>>{
      for (final entry in overrides.entries)
        _occasionId(entry.key): {
          'use24HourTime': entry.value.use24HourTime,
          'showSeconds': entry.value.showSeconds,
        },
    };
    await preferences.setString(_overridesKey, jsonEncode(encoded));
  }
}

String _occasionId(TimeDisplayOccasion occasion) {
  return switch (occasion) {
    TimeDisplayOccasion.submissionPublication => 'submission_publication',
    TimeDisplayOccasion.submissionComment => 'submission_comment',
    TimeDisplayOccasion.journalPublication => 'journal_publication',
    TimeDisplayOccasion.journalComment => 'journal_comment',
    TimeDisplayOccasion.profileJournal => 'profile_journal',
    TimeDisplayOccasion.profileRegistration => 'profile_registration',
    TimeDisplayOccasion.profileShout => 'profile_shout',
    TimeDisplayOccasion.notificationActivity => 'notification_activity',
    TimeDisplayOccasion.notificationShout => 'notification_shout',
    TimeDisplayOccasion.notesInbox => 'notes_inbox',
    TimeDisplayOccasion.notesSent => 'notes_sent',
    TimeDisplayOccasion.notesTrash => 'notes_trash',
    TimeDisplayOccasion.notesArchive => 'notes_archive',
    TimeDisplayOccasion.notePreview => 'note_preview',
    TimeDisplayOccasion.noteDetail => 'note_detail',
  };
}

TimeDisplayOccasion? _occasionFromId(String id) {
  for (final occasion in TimeDisplayOccasion.values) {
    if (_occasionId(occasion) == id) return occasion;
  }
  return null;
}
