import 'package:flutter/material.dart';

import 'package:FANotifier/features/settings/data/home_start_screen_preference.dart';

class SetHomeScreenScreen extends StatefulWidget {
  const SetHomeScreenScreen({super.key});

  @override
  State<SetHomeScreenScreen> createState() => _SetHomeScreenScreenState();
}

class _SetHomeScreenScreenState extends State<SetHomeScreenScreen> {
  static const Color _accent = Color(0xFFE09321);

  HomeStartScreenPreference _selectedPreference =
      HomeStartScreenPreference.browse;

  @override
  void initState() {
    super.initState();
    _loadPreference();
  }

  Future<void> _loadPreference() async {
    final preference = await loadHomeStartScreenPreference();
    if (!mounted) {
      return;
    }
    setState(() {
      _selectedPreference = preference;
    });
  }

  Future<void> _selectPreference(HomeStartScreenPreference preference) async {
    if (_selectedPreference == preference) {
      return;
    }
    setState(() {
      _selectedPreference = preference;
    });
    await saveHomeStartScreenPreference(preference);
  }

  Widget _buildOption({
    required HomeStartScreenPreference preference,
    required Widget icon,
  }) {
    final isSelected = _selectedPreference == preference;
    return ListTile(
      leading: icon,
      title: Text(preference.title),
      subtitle: Text(preference.subtitle),
      trailing: Icon(
        isSelected
            ? Icons.radio_button_checked
            : Icons.radio_button_unchecked,
        color: isSelected ? _accent : Colors.white70,
      ),
      onTap: () {
        _selectPreference(preference);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Set Home Screen'),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 8.0),
        children: [
          const SizedBox(height: 8),
          _buildOption(
            preference: HomeStartScreenPreference.browse,
            icon: const Icon(
              Icons.home,
              color: _accent,
            ),
          ),
          const Divider(
            height: 1.0,
            color: Color(0xFF111111),
            thickness: 3.0,
          ),
          _buildOption(
            preference: HomeStartScreenPreference.submissions,
            icon: Image.asset(
              'assets/icons/submissions.png',
              width: 27,
              height: 27,
              color: _accent,
            ),
          ),
          const Divider(
            height: 1.0,
            color: Color(0xFF111111),
            thickness: 3.0,
          ),
          _buildOption(
            preference: HomeStartScreenPreference.profile,
            icon: const Icon(
              Icons.account_circle_outlined,
              color: _accent,
            ),
          ),
          const Divider(
            height: 1.0,
            color: Color(0xFF111111),
            thickness: 3.0,
          ),
        ],
      ),
    );
  }
}
