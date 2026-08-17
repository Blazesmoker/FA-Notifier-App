import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:fanotifier/core/links/app_external_links.dart';
import 'package:fanotifier/features/settings/domain/fur_affinity_settings_models.dart';
import 'package:fanotifier/features/settings/domain/fur_affinity_settings_repository.dart';
import 'package:fanotifier/features/settings/presentation/fur_affinity_settings_widgets.dart';
import 'package:fanotifier/shared/utils/external_link_launcher.dart';
import 'package:fanotifier/shared/widgets/confirm_close_dialog.dart';
import 'package:fanotifier/shared/widgets/pulsating_loading_indicator.dart';

class FurAffinityGlobalSiteSettingsScreen extends StatefulWidget {
  const FurAffinityGlobalSiteSettingsScreen({super.key});

  @override
  State<FurAffinityGlobalSiteSettingsScreen> createState() =>
      _FurAffinityGlobalSiteSettingsScreenState();
}

class _FurAffinityGlobalSiteSettingsScreenState
    extends State<FurAffinityGlobalSiteSettingsScreen> {
  static const Set<String> _nativeFields = <String>{
    'disable_avatars',
    'hour_format',
    'date_format',
    'perpage',
    'newsubmissions_direction',
    'thumbnail_size',
    'gallery_navigation',
    'hide_favorites',
    'no_guests',
    'no_minors',
    'no_search_engines',
    'block_msg_submission_sender_younger_days',
    'block_msg_journal_sender_younger_days',
    'block_msg_shout_sender_younger_days',
    'block_msg_note_sender_younger_days',
    'no_notes',
    'search_order_by',
    'search_order_direction',
    'search_range',
    'search_rating_general',
    'search_rating_mature',
    'search_rating_adult',
    'search_content_type_art',
    'search_content_type_music',
    'search_content_type_flash',
    'search_content_type_story',
    'search_content_type_photo',
    'search_content_type_poetry',
  };
  static const Set<String> _checkboxFields = <String>{
    'search_rating_general',
    'search_rating_mature',
    'search_rating_adult',
    'search_content_type_art',
    'search_content_type_music',
    'search_content_type_flash',
    'search_content_type_story',
    'search_content_type_photo',
    'search_content_type_poetry',
  };

  late final FurAffinitySettingsRepository _repository;
  final Map<String, String?> _values = <String, String?>{};
  final Map<String, String?> _initialValues = <String, String?>{};

  FaSettingsFormSnapshot? _form;
  Object? _loadError;
  bool _loading = true;
  bool _saving = false;
  bool _allowPop = false;

  bool get _dirty {
    for (final name in _nativeFields) {
      if (_values[name] != _initialValues[name]) return true;
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    _repository = context.read<FurAffinitySettingsRepository>();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final form = await _repository.loadGlobalSiteSettings();
      if (!mounted) return;
      _applyForm(form);
      setState(() => _loading = false);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = error;
      });
    }
  }

  void _applyForm(FaSettingsFormSnapshot form) {
    _form = form;
    _values.clear();
    _initialValues.clear();
    for (final name in _nativeFields) {
      final field = form.field(name);
      if (field == null) continue;
      final value = _checkboxFields.contains(name)
          ? (field.checked ? (field.value.isEmpty ? 'on' : field.value) : null)
          : field.value;
      _values[name] = value;
      _initialValues[name] = value;
    }
  }

  Map<String, String?> _submissionValues() {
    final form = _form;
    if (form == null) return const <String, String?>{};
    final values = <String, String?>{};
    for (final name in _nativeFields) {
      if (form.field(name)?.enabled ?? false) {
        values[name] = _values[name];
      }
    }
    return values;
  }

  bool _enabled(String name) => _form?.field(name)?.enabled ?? false;

  String _label(String name) {
    final field = _form?.field(name);
    final value = _values[name] ?? field?.value ?? '';
    if (field == null) return value;
    for (final option in field.options) {
      if (option.value == value) return option.label;
    }
    return value;
  }

  Future<void> _selectValue(String name, String title) async {
    final field = _form?.field(name);
    if (field == null || !field.enabled || field.options.isEmpty) return;
    final selected = await showSettingsChoice(
      context,
      title: title,
      currentValue: _values[name] ?? '',
      options: field.options,
    );
    if (!mounted || selected == null) return;
    setState(() => _values[name] = selected);
  }

  void _setCheckbox(String name, bool value) {
    final fieldValue = _form?.field(name)?.value ?? '';
    setState(() {
      _values[name] = value ? (fieldValue.isEmpty ? '1' : fieldValue) : null;
    });
  }

  Future<void> _openFaPlus() async {
    var opened = false;
    try {
      opened = await tryLaunchExternalUri(AppExternalLinks.faPlusUri);
    } catch (_) {}
    if (!mounted || opened) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Colors.red.shade700,
        content: const Text('Could not open FA+ in the phone browser.'),
      ),
    );
  }

  Future<void> _save() async {
    if (!_dirty || _saving || _form == null) return;
    final values = _submissionValues();
    setState(() => _saving = true);
    final result = await _repository.saveGlobalSiteSettings(
      form: _form!,
      values: values,
    );
    if (!mounted) return;
    if (result.success) {
      _applyForm(result.returnedForm ?? _form!.withAppliedValues(values));
    }
    setState(() => _saving = false);
    showSettingsMutationSnackBar(
      context,
      section: 'Global Site',
      result: result,
    );
  }

  Future<void> _requestClose() async {
    if (_saving) return;
    if (!_dirty) {
      Navigator.of(context).pop();
      return;
    }
    final close = await ConfirmCloseDialog.show(
      context,
      title: 'Discard changes?',
      message: 'Your Global Site Settings changes have not been saved.',
    );
    if (!mounted || !close) return;
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  IosSettingsValueRow _choiceRow(
    String name,
    String title, {
    String? subtitle,
    Widget? subtitleWidget,
  }) {
    return IosSettingsValueRow(
      title: title,
      subtitle: subtitle,
      subtitleWidget: subtitleWidget,
      value: _label(name),
      enabled: _enabled(name),
      onTap: () => _selectValue(name, title),
    );
  }

  IosSettingsSwitchRow _checkboxRow(
    String name,
    String title, {
    bool compact = false,
  }) {
    return IosSettingsSwitchRow(
      title: title,
      value: _values[name] != null,
      enabled: _enabled(name),
      compact: compact,
      onChanged: (value) => _setCheckbox(name, value),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _allowPop || !_dirty,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _requestClose();
      },
      child: Scaffold(
        backgroundColor: furAffinitySettingsBackground,
        appBar: AppBar(
          title: const Text('Global Site Settings'),
          actions: [
            SettingsSaveAction(
              dirty: _dirty,
              saving: _saving,
              onPressed: _save,
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: _buildBody(),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: PulsatingLoadingIndicator(
          size: 78,
          assetPath: 'assets/icons/fathemed.png',
        ),
      );
    }
    if (_loadError != null || _form == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                settingsLoadFailureText(_loadError ?? 'Unknown error'),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 14),
              ElevatedButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.only(top: 8, bottom: 24),
      children: [
        IosSettingsSection(
          header: 'Site Settings',
          children: [
            IosSettingsSwitchRow(
              title: 'Disable Avatars',
              subtitle: 'Replace avatars with the default user icon.',
              value: _values['disable_avatars'] == '1',
              enabled: _enabled('disable_avatars'),
              onChanged: (value) => setState(
                () => _values['disable_avatars'] = value ? '1' : '0',
              ),
            ),
            _choiceRow('hour_format', 'Hour Format'),
            _choiceRow('date_format', 'Date Format'),
            _choiceRow(
              'perpage',
              'Submissions Per Page',
              subtitleWidget: IosSettingsPerkLink(
                message: 'Members get additional submissions to view per page.',
                iconUri: _form?.faPlusIconUri,
                onTap: _openFaPlus,
              ),
            ),
            _choiceRow(
              'newsubmissions_direction',
              'Submission Notifications Order',
            ),
            _choiceRow(
              'thumbnail_size',
              'Preferred Thumbnail Size',
              subtitleWidget: IosSettingsPerkLink(
                message:
                    'Members get an option for higher resolution previews.',
                iconUri: _form?.faPlusIconUri,
                onTap: _openFaPlus,
              ),
            ),
            _choiceRow(
              'gallery_navigation',
              'Submission Gallery Navigation',
            ),
          ],
        ),
        IosSettingsSection(
          header: 'Privacy Options',
          children: [
            _choiceRow('hide_favorites', 'Display Favorites'),
            _choiceRow('no_guests', 'Disable Guest Access'),
            _choiceRow('no_minors', 'Disable Access to Minors'),
            _choiceRow(
              'no_search_engines',
              'Disable Search Engine Indexing',
              subtitle:
                  'NOTE: This is automatically applied if the account is less than a year old and does not yet have more than 5 submissions.',
            ),
            _choiceRow(
              'block_msg_submission_sender_younger_days',
              'Limit Submission Comments',
            ),
            _choiceRow(
              'block_msg_journal_sender_younger_days',
              'Limit Journal Comments',
            ),
            _choiceRow(
              'block_msg_shout_sender_younger_days',
              'Limit Shouts',
            ),
            _choiceRow(
              'block_msg_note_sender_younger_days',
              'Limit Notes',
            ),
            _choiceRow('no_notes', 'Disable Notes'),
          ],
        ),
        IosSettingsSection(
          header: 'Search Settings',
          children: [
            _choiceRow('search_order_by', 'Order By'),
            _choiceRow('search_order_direction', 'Order Direction'),
            _choiceRow('search_range', 'Date Range'),
          ],
        ),
        IosSettingsSection(
          children: [
            _checkboxRow(
              'search_rating_general',
              'General',
              compact: true,
            ),
            _checkboxRow(
              'search_rating_mature',
              'Mature',
              compact: true,
            ),
            _checkboxRow(
              'search_rating_adult',
              'Adult',
              compact: true,
            ),
          ],
        ),
        IosSettingsSection(
          children: [
            _checkboxRow(
              'search_content_type_art',
              'Art',
              compact: true,
            ),
            _checkboxRow(
              'search_content_type_music',
              'Music',
              compact: true,
            ),
            _checkboxRow(
              'search_content_type_flash',
              'Flash',
              compact: true,
            ),
            _checkboxRow(
              'search_content_type_story',
              'Story',
              compact: true,
            ),
            _checkboxRow(
              'search_content_type_photo',
              'Photo',
              compact: true,
            ),
            _checkboxRow(
              'search_content_type_poetry',
              'Poetry',
              compact: true,
            ),
          ],
        ),
      ],
    );
  }
}
