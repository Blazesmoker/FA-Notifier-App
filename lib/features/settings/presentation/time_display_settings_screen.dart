import 'dart:async';

import 'package:fanotifier/features/settings/domain/time_display_models.dart';
import 'package:fanotifier/features/settings/presentation/fur_affinity_settings_widgets.dart';
import 'package:fanotifier/features/settings/presentation/time_display_settings_provider.dart';
import 'package:fanotifier/shared/utils/time_display_formatter.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

class _TimeDisplayOccasionSection {
  const _TimeDisplayOccasionSection(this.title, this.occasions);

  final String title;
  final List<TimeDisplayOccasion> occasions;
}

const List<_TimeDisplayOccasionSection> _occasionSections = [
  _TimeDisplayOccasionSection('Submissions', [
    TimeDisplayOccasion.submissionPublication,
    TimeDisplayOccasion.submissionComment,
  ]),
  _TimeDisplayOccasionSection('Journals', [
    TimeDisplayOccasion.journalPublication,
    TimeDisplayOccasion.journalComment,
    TimeDisplayOccasion.profileJournal,
  ]),
  _TimeDisplayOccasionSection('Profiles', [
    TimeDisplayOccasion.profileRegistration,
    TimeDisplayOccasion.profileShout,
  ]),
  _TimeDisplayOccasionSection('Notifications', [
    TimeDisplayOccasion.notificationActivity,
    TimeDisplayOccasion.notificationShout,
  ]),
  _TimeDisplayOccasionSection('Notes', [
    TimeDisplayOccasion.notesInbox,
    TimeDisplayOccasion.notesSent,
    TimeDisplayOccasion.notesTrash,
    TimeDisplayOccasion.notesArchive,
    TimeDisplayOccasion.notePreview,
    TimeDisplayOccasion.noteDetail,
  ]),
];

String _occasionLabel(TimeDisplayOccasion occasion) {
  return switch (occasion) {
    TimeDisplayOccasion.submissionPublication => 'Submission Publication',
    TimeDisplayOccasion.submissionComment => 'Submission Comments',
    TimeDisplayOccasion.journalPublication => 'Journal Publication',
    TimeDisplayOccasion.journalComment => 'Journal Comments',
    TimeDisplayOccasion.profileJournal => 'Profile Journal List',
    TimeDisplayOccasion.profileRegistration => 'Profile Registration',
    TimeDisplayOccasion.profileShout => 'Profile Shouts',
    TimeDisplayOccasion.notificationActivity => 'Activity Notifications',
    TimeDisplayOccasion.notificationShout => 'Notification Shouts',
    TimeDisplayOccasion.notesInbox => 'Notes Inbox',
    TimeDisplayOccasion.notesSent => 'Sent Notes',
    TimeDisplayOccasion.notesTrash => 'Trash Notes',
    TimeDisplayOccasion.notesArchive => 'Archived Notes',
    TimeDisplayOccasion.notePreview => 'Note Preview',
    TimeDisplayOccasion.noteDetail => 'Note Details',
  };
}

class _TimeDisplayPreviewText extends StatelessWidget {
  const _TimeDisplayPreviewText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        maxLines: 1,
        softWrap: false,
        style: const TextStyle(
          color: furAffinitySettingsSecondary,
          fontSize: 12,
          height: 1.25,
        ),
      ),
    );
  }
}

class _TimeDisplaySwitchRow extends StatelessWidget {
  const _TimeDisplaySwitchRow({
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.enabled = true,
  });

  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;
  final Widget? subtitle;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return IosSettingsRow(
      title: title,
      subtitleWidget: subtitle,
      enabled: enabled,
      onTap: enabled ? () => onChanged(!value) : null,
      trailing: Switch(
        value: value,
        activeThumbColor: furAffinitySettingsAccent,
        onChanged: enabled ? onChanged : null,
      ),
    );
  }
}

class TimeDisplaySettingsScreen extends StatefulWidget {
  const TimeDisplaySettingsScreen({super.key});

  @override
  State<TimeDisplaySettingsScreen> createState() =>
      _TimeDisplaySettingsScreenState();
}

class _TimeDisplaySettingsScreenState extends State<TimeDisplaySettingsScreen> {
  late DateTime _currentTime;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _currentTime = DateTime.now();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _currentTime = DateTime.now();
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<TimeDisplaySettingsProvider>();
    final currentTime = formatCurrentPhoneTime(
      _currentTime,
      format: settings.defaultFormat,
    );

    return Scaffold(
      backgroundColor: furAffinitySettingsBackground,
      appBar: AppBar(title: const Text('Time Display Settings')),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.only(top: 8, bottom: 24),
          children: [
            IosSettingsSection(
              header: 'Default Time Format',
              children: [
                _TimeDisplaySwitchRow(
                  title: '24-Hour Time',
                  value: settings.defaultFormat.use24HourTime,
                  onChanged: settings.setUse24HourTime,
                ),
                _TimeDisplaySwitchRow(
                  title: 'Show Seconds',
                  value: settings.defaultFormat.showSeconds,
                  onChanged: settings.setShowSeconds,
                  subtitle: _TimeDisplayPreviewText(
                    'Current phone time: $currentTime',
                  ),
                ),
              ],
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(32, 8, 32, 0),
              child: Text(
                'CUSTOMIZE BY OCCASION',
                style: TextStyle(
                  color: furAffinitySettingsSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                ),
              ),
            ),
            for (final section in _occasionSections)
              IosSettingsSection(
                header: section.title,
                children: [
                  for (final occasion in section.occasions)
                    IosSettingsRow(
                      title: _occasionLabel(occasion),
                      subtitleWidget: _TimeDisplayPreviewText(
                        '${settings.usesDefaultFormat(occasion) ? 'Default' : 'Custom'} · '
                        '${formatCurrentPhoneTime(
                          _currentTime,
                          format: settings.formatFor(occasion),
                        )}',
                      ),
                      trailing: const Icon(
                        Icons.chevron_right_rounded,
                        color: furAffinitySettingsSecondary,
                      ),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                _TimeDisplayOccasionSettingsScreen(
                              occasion: occasion,
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _TimeDisplayOccasionSettingsScreen extends StatefulWidget {
  const _TimeDisplayOccasionSettingsScreen({
    required this.occasion,
  });

  final TimeDisplayOccasion occasion;

  @override
  State<_TimeDisplayOccasionSettingsScreen> createState() =>
      _TimeDisplayOccasionSettingsScreenState();
}

class _TimeDisplayOccasionSettingsScreenState
    extends State<_TimeDisplayOccasionSettingsScreen> {
  late DateTime _currentTime;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _currentTime = DateTime.now();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _currentTime = DateTime.now();
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<TimeDisplaySettingsProvider>();
    final usesDefault = settings.usesDefaultFormat(widget.occasion);
    final format = settings.formatFor(widget.occasion);
    final currentTime = formatCurrentPhoneTime(
      _currentTime,
      format: format,
    );

    return Scaffold(
      backgroundColor: furAffinitySettingsBackground,
      appBar: AppBar(title: Text(_occasionLabel(widget.occasion))),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.only(top: 8, bottom: 24),
          children: [
            IosSettingsSection(
              header: 'Preview',
              children: [
                IosSettingsRow(
                  title: _occasionLabel(widget.occasion),
                  leading: const Icon(
                    Icons.access_time_rounded,
                    color: furAffinitySettingsAccent,
                  ),
                  subtitleWidget: _TimeDisplayPreviewText(
                    'Current phone time: $currentTime',
                  ),
                ),
              ],
            ),
            IosSettingsSection(
              header: 'Format',
              children: [
                _TimeDisplaySwitchRow(
                  title: 'Use Default Format',
                  value: usesDefault,
                  onChanged: (value) {
                    settings.setUsesDefaultFormat(widget.occasion, value);
                  },
                ),
                _TimeDisplaySwitchRow(
                  title: '24-Hour Time',
                  value: format.use24HourTime,
                  enabled: !usesDefault,
                  onChanged: (value) {
                    settings.setOccasionUse24HourTime(
                      widget.occasion,
                      value,
                    );
                  },
                ),
                _TimeDisplaySwitchRow(
                  title: 'Show Seconds',
                  value: format.showSeconds,
                  enabled: !usesDefault,
                  onChanged: (value) {
                    settings.setOccasionShowSeconds(
                      widget.occasion,
                      value,
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
