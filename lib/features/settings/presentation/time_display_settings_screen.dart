import 'dart:async';

import 'package:fanotifier/features/settings/domain/time_display_models.dart';
import 'package:fanotifier/features/settings/presentation/fur_affinity_settings_widgets.dart';
import 'package:fanotifier/features/settings/presentation/time_display_settings_provider.dart';
import 'package:fanotifier/shared/utils/time_display_formatter.dart';
import 'package:material_symbols_icons/symbols.dart';
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
    TimeDisplayOccasion.notesInbox => 'Notes Inbox',
    TimeDisplayOccasion.notesSent => 'Sent Notes',
    TimeDisplayOccasion.notesTrash => 'Trash Notes',
    TimeDisplayOccasion.notesArchive => 'Archived Notes',
    TimeDisplayOccasion.notePreview => 'Note Preview',
    TimeDisplayOccasion.noteDetail => 'Note Details',
  };
}

class _TimeDisplayPreviewText extends StatelessWidget {
  const _TimeDisplayPreviewText(
    this.text, {
    this.highlightCustom = false,
  });

  final String text;
  final bool highlightCustom;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: highlightCustom
          ? Text.rich(
              TextSpan(
                children: [
                  const TextSpan(
                    text: 'Custom',
                    style: TextStyle(color: furAffinitySettingsAccent),
                  ),
                  TextSpan(text: ' · $text'),
                ],
              ),
              maxLines: 1,
              softWrap: false,
              style: const TextStyle(
                color: furAffinitySettingsSecondary,
                fontSize: 12,
                height: 1.25,
              ),
            )
          : Text(
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

class _TimeDisplayAppBarTitle extends StatelessWidget {
  const _TimeDisplayAppBarTitle(this.text);

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
    this.verticalPadding = 12,
  });

  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;
  final Widget? subtitle;
  final double verticalPadding;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => onChanged(!value),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: 16,
            vertical: verticalPadding,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 5),
                      subtitle!,
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Switch(
                value: value,
                activeThumbColor: furAffinitySettingsAccent,
                onChanged: onChanged,
              ),
            ],
          ),
        ),
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

  Widget _buildOccasionRow(
    TimeDisplaySettingsProvider settings,
    TimeDisplayOccasion occasion,
  ) {
    final format = settings.formatFor(occasion);
    final usesDefault = settings.usesDefaultFormat(occasion);

    return _TimeDisplaySwitchRow(
      title: _occasionLabel(occasion),
      value: format.showSeconds,
      verticalPadding: 8,
      onChanged: (value) {
        settings.setOccasionShowSeconds(occasion, value);
      },
      subtitle: _TimeDisplayPreviewText(
        usesDefault
            ? 'Default · ${formatCurrentPhoneTime(
                _currentTime,
                format: format,
              )}'
            : formatCurrentPhoneTime(
                _currentTime,
                format: format,
              ),
        highlightCustom: !usesDefault,
      ),
    );
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
      appBar: AppBar(
        title: const _TimeDisplayAppBarTitle('Time Display Settings'),
        actions: [
          IconButton(
            tooltip: 'Reset time display settings',
            onPressed: settings.resetSettings,
            icon: const Icon(
              Symbols.reset_settings,
              color: furAffinitySettingsAccent,
              size: 24,
            ),
          ),
        ],
      ),
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
                'CUSTOMIZE SECONDS BY OCCASION',
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
                    _buildOccasionRow(settings, occasion),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
