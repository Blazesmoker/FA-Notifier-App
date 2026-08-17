import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:fanotifier/features/settings/domain/fur_affinity_settings_models.dart';
import 'package:fanotifier/features/settings/domain/fur_affinity_settings_repository.dart';
import 'package:fanotifier/features/settings/presentation/fur_affinity_settings_widgets.dart';
import 'package:fanotifier/shared/widgets/confirm_close_dialog.dart';
import 'package:fanotifier/shared/widgets/pulsating_loading_indicator.dart';

class FurAffinityUserSettingsScreen extends StatefulWidget {
  const FurAffinityUserSettingsScreen({super.key});

  @override
  State<FurAffinityUserSettingsScreen> createState() =>
      _FurAffinityUserSettingsScreenState();
}

class _FurAffinityUserSettingsScreenState
    extends State<FurAffinityUserSettingsScreen> {
  static const Set<String> _nativeFields = <String>{
    'accept_trades',
    'accept_commissions',
    'featured_journal_id',
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
      final form = await _repository.loadUserSettings();
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
      _values[name] = field.value;
      _initialValues[name] = field.value;
    }
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

  Future<void> _selectJournal() async {
    final field = _form?.field('featured_journal_id');
    if (field == null || !field.enabled || field.options.isEmpty) return;
    final selected = await showSettingsChoice(
      context,
      title: 'Featured Journal',
      currentValue: _values['featured_journal_id'] ?? '',
      options: field.options,
    );
    if (!mounted || selected == null) return;
    setState(() => _values['featured_journal_id'] = selected);
  }

  Map<String, String?> _submissionValues() {
    final values = <String, String?>{};
    for (final name in _nativeFields) {
      if (_enabled(name)) values[name] = _values[name];
    }
    return values;
  }

  Future<void> _save() async {
    if (!_dirty || _saving || _form == null) return;
    final values = _submissionValues();
    setState(() => _saving = true);
    final result = await _repository.saveUserSettings(
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
      section: 'User',
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
      message: 'Your User Settings changes have not been saved.',
    );
    if (!mounted || !close) return;
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
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
          title: const Text('User Settings'),
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
          header: 'User Settings',
          children: [
            IosSettingsSwitchRow(
              title: 'Accepting Trades',
              subtitle: 'Displayed on your Fur Affinity userpage.',
              value: _values['accept_trades'] == '1',
              enabled: _enabled('accept_trades'),
              onChanged: (value) => setState(
                () => _values['accept_trades'] = value ? '1' : '0',
              ),
            ),
            IosSettingsSwitchRow(
              title: 'Accepting Commissions',
              subtitle: 'Displayed on your Fur Affinity userpage.',
              value: _values['accept_commissions'] == '1',
              enabled: _enabled('accept_commissions'),
              onChanged: (value) => setState(
                () => _values['accept_commissions'] = value ? '1' : '0',
              ),
            ),
            IosSettingsValueRow(
              title: 'Featured Journal',
              subtitle: 'Choose the journal displayed on your userpage.',
              value: _label('featured_journal_id'),
              enabled: _enabled('featured_journal_id'),
              onTap: _selectJournal,
              stacked: true,
            ),
          ],
        ),
      ],
    );
  }
}
