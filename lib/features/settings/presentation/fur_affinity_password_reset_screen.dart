import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:fanotifier/features/settings/domain/fur_affinity_settings_repository.dart';
import 'package:fanotifier/features/settings/presentation/fur_affinity_settings_widgets.dart';
import 'package:fanotifier/shared/widgets/confirm_close_dialog.dart';

class FurAffinityPasswordResetScreen extends StatefulWidget {
  const FurAffinityPasswordResetScreen({
    super.key,
    this.onSessionInvalidated,
  });

  final VoidCallback? onSessionInvalidated;

  @override
  State<FurAffinityPasswordResetScreen> createState() =>
      _FurAffinityPasswordResetScreenState();
}

class _FurAffinityPasswordResetScreenState
    extends State<FurAffinityPasswordResetScreen> {
  static const List<String> _fieldNames = <String>[
    'request_username',
    'request_email',
    'reset_username',
    'reset_email',
    'verification_code',
    'new_password',
    'confirmed_password',
  ];

  late final FurAffinitySettingsRepository _repository;
  final Map<String, TextEditingController> _controllers =
      <String, TextEditingController>{};
  final Map<String, String> _baseline = <String, String>{};

  bool _sendingCode = false;
  bool _resettingPassword = false;
  bool _allowPop = false;
  bool _settingControllers = false;

  bool get _dirty {
    for (final name in _fieldNames) {
      if ((_controllers[name]?.text ?? '') != (_baseline[name] ?? '')) {
        return true;
      }
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    _repository = context.read<FurAffinitySettingsRepository>();
    for (final name in _fieldNames) {
      _baseline[name] = '';
      final controller = TextEditingController();
      controller.addListener(() {
        if (!mounted || _settingControllers) return;
        setState(() {});
      });
      _controllers[name] = controller;
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  TextEditingController _controller(String name) => _controllers[name]!;

  Future<void> _sendCode() async {
    if (_sendingCode || _resettingPassword) return;
    final username = _controller('request_username').text.trim();
    final email = _controller('request_email').text.trim();
    if (username.isEmpty || email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red.shade700,
          content: const Text('Username and Email Address are required.'),
        ),
      );
      return;
    }

    setState(() => _sendingCode = true);
    final result = await _repository.sendPasswordRecoveryCode(
      username: username,
      email: email,
    );
    if (!mounted) return;
    if (result.success) {
      _baseline['request_username'] = _controller('request_username').text;
      _baseline['request_email'] = _controller('request_email').text;
    }
    setState(() => _sendingCode = false);
    showSettingsMutationSnackBar(
      context,
      section: 'Password recovery',
      result: result,
      successText: 'Password recovery code sent successfully.',
      failureText: 'Password recovery code request failed',
    );
  }

  Future<void> _resetPassword() async {
    if (_sendingCode || _resettingPassword) return;
    final username = _controller('reset_username').text.trim();
    final email = _controller('reset_email').text.trim();
    final code = _controller('verification_code').text.trim();
    final password = _controller('new_password').text;
    final confirmedPassword = _controller('confirmed_password').text;

    String? validation;
    if (username.isEmpty || email.isEmpty || code.isEmpty) {
      validation = 'Username, Email Address, and Verification Code are required.';
    } else if (password.length < 6) {
      validation = 'New password must be at least 6 characters.';
    } else if (password.length > 72) {
      validation = 'New password must not exceed 72 characters.';
    } else if (password != confirmedPassword) {
      validation = 'New passwords do not match.';
    }
    if (validation != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red.shade700,
          content: Text(validation),
        ),
      );
      return;
    }

    setState(() => _resettingPassword = true);
    final result = await _repository.resetPassword(
      username: username,
      email: email,
      verificationCode: code,
      newPassword: password,
      confirmedPassword: confirmedPassword,
    );
    if (!mounted) return;
    if (result.success) _clearFields();
    setState(() => _resettingPassword = false);
    showSettingsMutationSnackBar(
      context,
      section: 'Password reset',
      result: result,
      successText: 'Password reset successfully.',
      failureText: 'Password reset failed',
    );

    if (result.success) {
      await Future<void>.delayed(const Duration(milliseconds: 900));
      if (mounted) widget.onSessionInvalidated?.call();
    }
  }

  void _clearFields() {
    _settingControllers = true;
    for (final name in _fieldNames) {
      _controllers[name]!.clear();
      _baseline[name] = '';
    }
    _settingControllers = false;
  }

  Future<void> _requestClose() async {
    if (_sendingCode || _resettingPassword) return;
    if (!_dirty) {
      Navigator.of(context).pop();
      return;
    }
    final close = await ConfirmCloseDialog.show(
      context,
      title: 'Discard entered information?',
      message: 'Your password recovery information has not been submitted.',
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
        appBar: AppBar(title: const Text('Password Reset')),
        body: SafeArea(
          top: false,
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.only(top: 8, bottom: 24),
            children: [
              IosSettingsSection(
                header: 'Step 1 - Password Recovery',
                footer:
                    'Use the account Username. A Display Name will not work.',
                children: [
                  IosSettingsTextFieldRow(
                    title: 'Username',
                    controller: _controller('request_username'),
                    autofillHints: const [AutofillHints.username],
                  ),
                  IosSettingsTextFieldRow(
                    title: 'Email Address',
                    controller: _controller('request_email'),
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                  ),
                  IosSettingsActionButton(
                    label: 'Send Code',
                    loading: _sendingCode,
                    onPressed: _sendCode,
                  ),
                ],
              ),
              const IosSettingsSection(
                header: 'Step 2 - Be Patient!',
                children: [
                  IosSettingsRow(
                    title: 'Email delivery can take up to 15 minutes.',
                    subtitle:
                        'Add noreply@furaffinity.net to your contacts or whitelist. If the message does not arrive, check your spam or junk folder. Resetting the password signs the account out of all active sessions.',
                  ),
                ],
              ),
              IosSettingsSection(
                header: 'Step 3 - Verification',
                footer:
                    'Provide every field after receiving the verification code. Use the account Username, not the Display Name.',
                children: [
                  IosSettingsTextFieldRow(
                    title: 'Username',
                    controller: _controller('reset_username'),
                    autofillHints: const [AutofillHints.username],
                  ),
                  IosSettingsTextFieldRow(
                    title: 'Email Address',
                    controller: _controller('reset_email'),
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                  ),
                  IosSettingsTextFieldRow(
                    title: 'Verification Code',
                    controller: _controller('verification_code'),
                    keyboardType: TextInputType.text,
                  ),
                  IosSettingsTextFieldRow(
                    title: 'New Password',
                    subtitle: 'Must be at least 6 characters.',
                    controller: _controller('new_password'),
                    obscureText: true,
                    maxLength: 72,
                    autofillHints: const [AutofillHints.newPassword],
                  ),
                  IosSettingsTextFieldRow(
                    title: 'Confirm Password',
                    controller: _controller('confirmed_password'),
                    obscureText: true,
                    maxLength: 72,
                    autofillHints: const [AutofillHints.newPassword],
                  ),
                  IosSettingsActionButton(
                    label: 'Reset Password',
                    loading: _resettingPassword,
                    onPressed: _resetPassword,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
