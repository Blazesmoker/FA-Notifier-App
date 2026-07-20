import 'dart:io';

import 'package:fanotifier/features/settings/domain/app_icon_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

class AppIconSettingsScreen extends StatefulWidget {
  const AppIconSettingsScreen({super.key});

  @override
  State<AppIconSettingsScreen> createState() => _AppIconSettingsScreenState();
}

class _AppIconSettingsScreenState extends State<AppIconSettingsScreen> {
  late final AppIconRepository _appIconRepository;

  bool useAdaptiveIcon = false;

  @override
  void initState() {
    super.initState();
    _appIconRepository = context.read<AppIconRepository>();
    _loadIconPreference();
  }

  Future<void> _loadIconPreference() async {
    final loadedUseAdaptiveIcon =
        await _appIconRepository.loadUseAdaptiveIcon();
    if (!mounted) return;
    setState(() {
      useAdaptiveIcon = loadedUseAdaptiveIcon;
    });
  }

  Future<void> _toggleIcon(bool value) async {
    setState(() => useAdaptiveIcon = value);

    try {
      await _appIconRepository.setUseAdaptiveIcon(useAdaptiveIcon);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.green,
          content: Text(
            'Icon switched to ${useAdaptiveIcon ? 'Adaptive' : 'Transparent'}. Restarting...',
            style: const TextStyle(color: Colors.white),
          ),
        ),
      );
    } on PlatformException catch (e) {
      debugPrint("Error switching icon: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('App Icon')),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0),
          child: Column(
            children: [
              const SizedBox(height: 8),

              if (Platform.isAndroid)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Align(
                        alignment: Alignment.center,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Text(
                              'Transparent icon',
                              style: TextStyle(fontSize: 14),
                              textAlign: TextAlign.center,
                            ),
                            SizedBox(height: 2),
                            Text(
                              '(if supported)',
                              style: TextStyle(fontSize: 11, color: Colors.grey),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
                    Center(
                      child: Switch(
                        value: useAdaptiveIcon,
                        activeThumbColor: const Color(0xFFE09321),
                        onChanged: _toggleIcon,
                      ),
                    ),
                    Expanded(
                      child: Align(
                        alignment: Alignment.center,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Text(
                              'Adaptive icon',
                              style: TextStyle(fontSize: 14),
                              textAlign: TextAlign.center,
                            ),
                            SizedBox(height: 2),
                            Text(
                              '(theme supported)',
                              style: TextStyle(fontSize: 11, color: Colors.grey),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),

              const SizedBox(height: 8),
              const Divider(
                height: 1.0,
                color: Color(0xFF111111),
                thickness: 3.0,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
