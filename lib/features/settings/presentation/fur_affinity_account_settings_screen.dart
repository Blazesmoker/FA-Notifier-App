import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:fanotifier/core/analytics/app_screen.dart';
import 'package:fanotifier/core/links/app_external_links.dart';
import 'package:fanotifier/features/settings/domain/fur_affinity_settings_models.dart';
import 'package:fanotifier/features/settings/domain/fur_affinity_settings_repository.dart';
import 'package:fanotifier/features/settings/presentation/fur_affinity_password_reset_screen.dart';
import 'package:fanotifier/features/settings/presentation/fur_affinity_settings_widgets.dart';
import 'package:fanotifier/shared/utils/external_link_launcher.dart';
import 'package:fanotifier/shared/widgets/confirm_close_dialog.dart';
import 'package:fanotifier/shared/widgets/pulsating_loading_indicator.dart';

class FurAffinityAccountSettingsScreen extends StatefulWidget {
  const FurAffinityAccountSettingsScreen({
    super.key,
    this.onSessionInvalidated,
  });

  final VoidCallback? onSessionInvalidated;

  @override
  State<FurAffinityAccountSettingsScreen> createState() =>
      _FurAffinityAccountSettingsScreenState();
}

class _FurAffinityAccountSettingsScreenState
    extends State<FurAffinityAccountSettingsScreen> {
  static const Set<String> _nativeFields = <String>{
    'fa_useremail',
    'viewmature',
    'timezone',
    'timezone_dst',
    'fullview',
    'scales_enabled',
    'paypal_email',
    'display_mode',
    'scales_message_enabled',
    'scales_name',
    'scales_plural_name',
    'scales_cost',
    'wall_of_awesome_hidden',
    'newpassword',
    'newpassword2',
  };
  static const Set<String> _checkboxFields = <String>{'timezone_dst'};
  static const Set<String> _textFields = <String>{
    'fa_useremail',
    'paypal_email',
    'scales_name',
    'scales_plural_name',
    'scales_cost',
    'newpassword',
    'newpassword2',
  };

  late final FurAffinitySettingsRepository _repository;
  final Map<String, String?> _values = <String, String?>{};
  final Map<String, String?> _initialValues = <String, String?>{};
  final Map<String, TextEditingController> _controllers =
      <String, TextEditingController>{};

  FaSettingsFormSnapshot? _form;
  Object? _loadError;
  bool _loading = true;
  bool _saving = false;
  bool _allowPop = false;
  bool _settingControllers = false;

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

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final form = await _repository.loadAccountSettings();
      if (!mounted) return;
      _applyForm(form);
      setState(() {
        _loading = false;
      });
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
    _settingControllers = true;
    for (final name in _textFields) {
      final text = _values[name] ?? '';
      final existing = _controllers[name];
      if (existing == null) {
        final controller = TextEditingController(text: text);
        controller.addListener(() {
          if (!mounted || _settingControllers) return;
          setState(() => _values[name] = controller.text);
        });
        _controllers[name] = controller;
      } else {
        existing.text = text;
      }
    }
    _settingControllers = false;
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

  String _label(String name) {
    final field = _form?.field(name);
    final value = _values[name] ?? field?.value ?? '';
    if (field == null) return value;
    for (final option in field.options) {
      if (option.value == value) return option.label;
    }
    return value;
  }

  bool _enabled(String name) => _form?.field(name)?.enabled ?? false;

  TextEditingController _controller(String name) {
    return _controllers[name] ??= TextEditingController();
  }

  Future<void> _openExternal(Uri uri, String label) async {
    var opened = false;
    try {
      opened = await tryLaunchExternalUri(uri);
    } catch (_) {}
    if (!mounted || opened) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Colors.red.shade700,
        content: Text('Could not open $label in the phone browser.'),
      ),
    );
  }

  Future<void> _openPasswordReset() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        settings: const AnalyticsRouteSettings(
          AppScreens.furAffinityPasswordReset,
        ),
        builder: (_) => FurAffinityPasswordResetScreen(
          onSessionInvalidated: widget.onSessionInvalidated,
        ),
      ),
    );
  }

  String? _validate() {
    if ((_values['fa_useremail'] ?? '').trim().isEmpty) {
      return 'Email Address is required.';
    }
    final newPassword = _values['newpassword'] ?? '';
    final confirmedPassword = _values['newpassword2'] ?? '';
    if (newPassword.isNotEmpty || confirmedPassword.isNotEmpty) {
      if (newPassword.length < 6) {
        return 'New password must be at least 6 characters.';
      }
      if (newPassword.length > 72) {
        return 'New password must not exceed 72 characters.';
      }
      if (newPassword != confirmedPassword) {
        return 'New passwords do not match.';
      }
    }
    final costField = _form?.field('scales_cost');
    final costText = (_values['scales_cost'] ?? '').trim();
    if ((costField?.enabled ?? false) && costText.isNotEmpty) {
      final cost = int.tryParse(costText);
      final min = int.tryParse(costField?.min ?? '') ?? 1;
      final max = int.tryParse(costField?.max ?? '') ?? 100;
      if (cost == null || cost < min || cost > max) {
        return 'Tip Price must be between $min and $max.';
      }
    }
    return null;
  }

  Future<String?> _requestCurrentPassword() async {
    final controller = TextEditingController();
    String? errorText;
    final password = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Verify Password'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'In order to save changes we need to verify your password.',
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: () {
                    Navigator.of(dialogContext).pop();
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) _openPasswordReset();
                    });
                  },
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          'Having issues? Reset your password',
                          style: TextStyle(color: furAffinitySettingsAccent),
                        ),
                      ),
                      SizedBox(width: 6),
                      Icon(
                        Icons.open_in_new_rounded,
                        size: 17,
                        color: furAffinitySettingsAccent,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  autofocus: true,
                  obscureText: true,
                  maxLength: 72,
                  autofillHints: const [AutofillHints.password],
                  decoration: InputDecoration(
                    labelText: 'Current Password',
                    errorText: errorText,
                    counterText: '',
                  ),
                  onSubmitted: (_) {
                    final value = controller.text;
                    if (value.isEmpty) {
                      setDialogState(
                        () => errorText = 'Current Password is required.',
                      );
                    } else {
                      Navigator.of(dialogContext).pop(value);
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                final value = controller.text;
                if (value.isEmpty) {
                  setDialogState(
                    () => errorText = 'Current Password is required.',
                  );
                  return;
                }
                Navigator.of(dialogContext).pop(value);
              },
              child: const Text(
                'Save Changes',
                style: TextStyle(color: furAffinitySettingsAccent),
              ),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    return password;
  }

  Future<void> _save() async {
    if (!_dirty || _saving || _form == null) return;
    final validation = _validate();
    if (validation != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red.shade700,
          content: Text(validation),
        ),
      );
      return;
    }
    final currentPassword = await _requestCurrentPassword();
    if (!mounted || currentPassword == null) return;

    final values = _submissionValues();
    final passwordChanged = (values['newpassword'] ?? '').isNotEmpty;
    setState(() => _saving = true);
    final result = await _repository.saveAccountSettings(
      form: _form!,
      values: values,
      currentPassword: currentPassword,
    );
    if (!mounted) return;

    if (result.success) {
      final appliedValues = Map<String, String?>.from(values)
        ..['newpassword'] = ''
        ..['newpassword2'] = '';
      final nextForm = result.returnedForm ??
          _form!.withAppliedValues(appliedValues);
      _applyForm(nextForm);
    }
    setState(() => _saving = false);
    showSettingsMutationSnackBar(
      context,
      section: 'Account',
      result: result,
    );

    if (result.success && passwordChanged) {
      await Future<void>.delayed(const Duration(milliseconds: 900));
      if (mounted) widget.onSessionInvalidated?.call();
    }
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
      message: 'Your Account Settings changes have not been saved.',
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
          title: const Text('Account Settings'),
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
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.only(top: 8, bottom: 24),
      children: [
        IosSettingsSection(
          header: 'Account Settings',
          children: [
            IosSettingsTextFieldRow(
              title: 'Email Address (Required)',
              subtitle: 'Used for password resets and account recovery.',
              controller: _controller('fa_useremail'),
              enabled: _enabled('fa_useremail'),
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
            ),
            IosSettingsLinkRow(
              title: 'Date of Birth',
              subtitle:
                  'Note: You can only change your date of birth up to 3 times.',
              onTap: () => _openExternal(
                AppExternalLinks.faAccountSettingsUri,
                'Date of Birth',
              ),
            ),
            IosSettingsValueRow(
              title: 'Enable Adult Artwork',
              subtitle: _enabled('viewmature')
                  ? 'Choose the content ratings visible to this account.'
                  : 'Unavailable while browsing in SFW mode.',
              value: _label('viewmature'),
              enabled: _enabled('viewmature'),
              onTap: () => _selectValue(
                'viewmature',
                'Enable Adult Artwork',
              ),
            ),
            IosSettingsValueRow(
              title: 'Time Zone',
              subtitle:
                  'NOTE: This only affects server-side date calculations, in the case that javascript is unavailable. When it is, it uses your local timezone data instead.',
              value: _label('timezone'),
              enabled: _enabled('timezone'),
              onTap: () => _selectValue('timezone', 'Time Zone'),
            ),
            IosSettingsSwitchRow(
              title: 'Force Daylight Saving Time',
              value: _values['timezone_dst'] != null,
              enabled: _enabled('timezone_dst'),
              onChanged: (value) => setState(
                () => _values['timezone_dst'] = value
                    ? (_form!.field('timezone_dst')?.value ?? '1')
                    : null,
              ),
            ),
          ],
        ),
        IosSettingsSection(
          header: 'Account Personalization',
          children: [
            IosSettingsValueRow(
              title: 'Image Full View',
              subtitle: 'Choose thumbnails or full-resolution images.',
              value: _label('fullview'),
              enabled: _enabled('fullview'),
              onTap: () => _selectValue('fullview', 'Image Full View'),
            ),
            IosSettingsLinkRow(
              title: 'Site Layout/Theme',
              subtitle:
                  'NOTE: The Classic theme is being deprecated and will only receive maintanence updates. Please use Modern!',
              onTap: () => _openExternal(
                AppExternalLinks.faAccountSettingsUri,
                'Site Layout/Theme',
              ),
            ),
            IosSettingsLinkRow(
              title: 'Theme Overrides',
              subtitle: 'Manage this setting on Fur Affinity.',
              onTap: () => _openExternal(
                AppExternalLinks.faAccountSettingsUri,
                'Theme Overrides',
              ),
            ),
          ],
        ),
        IosSettingsSection(
          header: 'Shinies Tip Settings',
          children: [
            IosSettingsValueRow(
              title: 'Enable Shinies Tipping System',
              value: _label('scales_enabled'),
              enabled: _enabled('scales_enabled'),
              onTap: () => _selectValue(
                'scales_enabled',
                'Enable Shinies Tipping System',
              ),
            ),
            IosSettingsTextFieldRow(
              title: 'PayPal Address',
              subtitle: 'This address may be visible during P2P transactions.',
              controller: _controller('paypal_email'),
              enabled: _enabled('paypal_email'),
              keyboardType: TextInputType.emailAddress,
            ),
            IosSettingsValueRow(
              title: 'Display Donation Feed',
              value: _label('display_mode'),
              enabled: _enabled('display_mode'),
              onTap: () => _selectValue(
                'display_mode',
                'Display Donation Feed',
              ),
            ),
            IosSettingsValueRow(
              title: 'Allow Users to Leave Comments',
              subtitle:
                  'NOTE: This will not hide existing messages. You will have to hide them manually.',
              value: _label('scales_message_enabled'),
              enabled: _enabled('scales_message_enabled'),
              onTap: () => _selectValue(
                'scales_message_enabled',
                'Allow Users to Leave Comments',
              ),
            ),
            IosSettingsTextFieldRow(
              title: 'Tip Name',
              subtitle: _enabled('scales_name')
                  ? 'Singular name for tips.'
                  : 'Available to subscribers only.',
              controller: _controller('scales_name'),
              enabled: _enabled('scales_name'),
            ),
            IosSettingsTextFieldRow(
              title: 'Plural Tip Name',
              controller: _controller('scales_plural_name'),
              enabled: _enabled('scales_plural_name'),
            ),
            IosSettingsTextFieldRow(
              title: 'Tip Price',
              subtitle: _enabled('scales_cost')
                  ? 'Enter a value from 1 to 100.'
                  : 'Available to subscribers only.',
              controller: _controller('scales_cost'),
              enabled: _enabled('scales_cost'),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        IosSettingsSection(
          header: 'Privacy settings',
          children: [
            IosSettingsValueRow(
              title: 'Wall of Awesome visibility',
              subtitle:
                  'NOTE: You must also have your Subscription visibility set to "Show Subscriber badge" to be visible on the wall. This change may take up to an hour to be reflected on the wall.',
              value: _label('wall_of_awesome_hidden'),
              enabled: _enabled('wall_of_awesome_hidden'),
              onTap: () => _selectValue(
                'wall_of_awesome_hidden',
                'Wall of Awesome visibility',
              ),
            ),
          ],
        ),
        IosSettingsSection(
          header: 'Disable / Delete Your Account',
          children: [
            IosSettingsLinkRow(
              title: 'Disable Account',
              subtitle: 'Manage this setting on Fur Affinity.',
              onTap: () => _openExternal(
                AppExternalLinks.faAccountSettingsUri,
                'Disable Account',
              ),
            ),
            IosSettingsLinkRow(
              title: 'Delete Account',
              subtitle: 'Continue to Fur Affinity’s account deletion flow.',
              onTap: () => _openExternal(
                AppExternalLinks.faDeleteAccountUri,
                'Delete Account',
              ),
            ),
          ],
        ),
        IosSettingsSection(
          header: 'Update Your Password',
          footer:
              'Changing your password signs out all currently active sessions.',
          children: [
            IosSettingsTextFieldRow(
              title: 'New Password',
              subtitle: 'Must be at least 6 characters.',
              controller: _controller('newpassword'),
              enabled: _enabled('newpassword'),
              obscureText: true,
              maxLength: 72,
              autofillHints: const [AutofillHints.newPassword],
            ),
            IosSettingsTextFieldRow(
              title: 'Verify New Password',
              controller: _controller('newpassword2'),
              enabled: _enabled('newpassword2'),
              obscureText: true,
              maxLength: 72,
              autofillHints: const [AutofillHints.newPassword],
            ),
            IosSettingsLinkRow(
              title: 'Reset Password',
              subtitle: 'Use a verification code to create a new password.',
              onTap: _openPasswordReset,
            ),
          ],
        ),
      ],
    );
  }
}
