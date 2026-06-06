import 'package:FANotifier/app/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher_string.dart';

class UpdateScreen extends StatelessWidget {
  const UpdateScreen({
    super.key,
    required this.canDismiss,
  });

  final bool canDismiss;

  static const Color _backgroundColor = Color(0xFF111111);
  static const Color _updateColor = Color(0xFFE09321);

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: canDismiss,
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
            child: Stack(
              children: [
                if (canDismiss)
                  Align(
                    alignment: Alignment.topRight,
                    child: IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      padding: const EdgeInsets.all(20),
                      icon: const Icon(
                        Icons.close,
                        color: Colors.white54,
                        size: 30,
                      ),
                    ),
                  ),
                Center(
                  child: Transform.translate(
                    offset: const Offset(0, -44),
                    child: const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Image(
                          image: AssetImage('assets/icons/fathemed.png'),
                          width: 150,
                          height: 150,
                        ),
                        SizedBox(height: 28),
                        Text(
                          'New Update Available!',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        FilledButton(
                          onPressed: () => launchUrlString(
                            'https://t.me/+xTEmmXoDW5tkMGFi',
                            mode: LaunchMode.externalApplication,
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: _updateColor,
                            foregroundColor: _backgroundColor,
                            minimumSize: const Size.fromHeight(52),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(26),
                            ),
                          ),
                          child: const Text(
                            'Update now',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        if (canDismiss)
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            style: TextButton.styleFrom(
                              foregroundColor: AppTheme.lightGrey,
                              overlayColor: Colors.transparent,
                              splashFactory: NoSplash.splashFactory,
                            ),
                            child: const Text('Not now'),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
