import 'dart:async';

import 'package:fanotifier/features/settings/presentation/time_display_settings_provider.dart';
import 'package:fanotifier/shared/utils/time_display_formatter.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

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
      use24HourTime: settings.use24HourTime,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Time Display Settings')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          children: [
            const SizedBox(height: 8),
            const ListTile(
              leading: Icon(
                Icons.access_time_rounded,
                color: Color(0xFFE09321),
              ),
              title: Text('Time Display'),
            ),
            SwitchListTile(
              activeThumbColor: const Color(0xFFE09321),
              value: settings.use24HourTime,
              onChanged: settings.setUse24HourTime,
              title: const Text('24-Hour Time'),
              subtitle: Text('Current phone time: $currentTime'),
            ),
          ],
        ),
      ),
    );
  }
}
