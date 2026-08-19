import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:fanotifier/core/preferences/privacy_settings_provider.dart';
import 'package:fanotifier/shared/theme/app_theme.dart';
import 'package:fanotifier/shared/widgets/cooldown_send_icon.dart';

class PrivacyConsentScreen extends StatefulWidget {
  const PrivacyConsentScreen({super.key, required this.onCompleted});

  final VoidCallback onCompleted;

  @override
  State<PrivacyConsentScreen> createState() => _PrivacyConsentScreenState();
}

class _PrivacyConsentScreenState extends State<PrivacyConsentScreen> {
  static const int _countdownTotal = 5;
  static const Color _backgroundColor = AppTheme.background;
  static const Color _accentColor = Color(0xFFE09321);

  int _countdownRemaining = _countdownTotal;
  Timer? _countdownTimer;
  Timer? _countdownDisposeTimer;
  bool _countdownHidden = false;
  bool _isSubmitting = false;
  bool _analyticsEnabled = true;
  bool _crashlyticsEnabled = true;

  @override
  void initState() {
    super.initState();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_countdownRemaining <= 1) {
        timer.cancel();
        setState(() {
          _countdownRemaining = 0;
        });
        _countdownDisposeTimer = Timer(const Duration(seconds: 1), () {
          if (!mounted) return;
          setState(() {
            _countdownHidden = true;
          });
        });
      } else {
        setState(() {
          _countdownRemaining--;
        });
      }
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _countdownDisposeTimer?.cancel();
    super.dispose();
  }

  bool get _controlsDisabled => !_countdownHidden || _isSubmitting;

  Future<void> _complete() async {
    if (_controlsDisabled) return;
    setState(() {
      _isSubmitting = true;
    });
    final provider = context.read<PrivacySettingsProvider>();
    await provider.completeConsent(
      analyticsEnabled: _analyticsEnabled,
      crashlyticsEnabled: _crashlyticsEnabled,
    );
    if (!mounted) return;
    widget.onCompleted();
  }

  Widget _buildCountdown() {
    if (!_countdownHidden) {
      return CooldownSendIcon(
        remainingSeconds: _countdownRemaining,
        totalSeconds: _countdownTotal,
      );
    }
    return const SizedBox(width: 28, height: 28);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: const SystemUiOverlayStyle(
          statusBarColor: _backgroundColor,
          statusBarIconBrightness: Brightness.light,
          systemNavigationBarColor: _backgroundColor,
          systemNavigationBarIconBrightness: Brightness.light,
        ),
        child: Scaffold(
          backgroundColor: _backgroundColor,
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: IntrinsicHeight(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Spacer(flex: 2),
                            Center(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Text(
                                      'Help improve FA Notifier',
                                      textAlign: TextAlign.center,
                                      style: AppTheme.headline,
                                    ),
                                    const SizedBox(width: 6),
                                    Image.asset(
                                      'assets/icons/fathemed.png',
                                      width: 21,
                                      height: 21,
                                      fit: BoxFit.contain,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'FA Notifier can use Google Firebase Analytics '
                              'to understand which countries the app is used '
                              'from and which screens are used most often, '
                              'and Google Firebase Crashlytics to detect '
                              'crashes and diagnose technical errors. This '
                              'data is not used for advertising or tracking, '
                              'and FA Notifier does not collect your Fur '
                              'Affinity credentials, messages, or other '
                              'personal content for these purposes.',
                              textAlign: TextAlign.center,
                              style: AppTheme.body1,
                            ),
                            const SizedBox(height: 24),
                            SwitchListTile(
                              activeThumbColor: _accentColor,
                              title: const Text('Google Firebase Analytics'),
                              value: _analyticsEnabled,
                              onChanged: (value) {
                                setState(() {
                                  _analyticsEnabled = value;
                                });
                              },
                            ),
                            SwitchListTile(
                              activeThumbColor: _accentColor,
                              title: const Text('Google Firebase Crashlytics'),
                              value: _crashlyticsEnabled,
                              onChanged: (value) {
                                setState(() {
                                  _crashlyticsEnabled = value;
                                });
                              },
                            ),
                            const Spacer(flex: 1),
                            _buildCountdown(),
                            const Spacer(flex: 1),
                            FilledButton(
                              onPressed: _controlsDisabled
                                  ? null
                                  : _complete,
                              style: FilledButton.styleFrom(
                                backgroundColor: _accentColor,
                                foregroundColor: _backgroundColor,
                                overlayColor: Colors.transparent,
                                splashFactory: NoSplash.splashFactory,
                                minimumSize: const Size.fromHeight(52),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(26),
                                ),
                              ),
                              child: const Text(
                                'Confirm',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(height: 32),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}