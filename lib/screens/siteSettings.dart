import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_switch/flutter_switch.dart';

class SiteSettingsScreen extends StatefulWidget {
  const SiteSettingsScreen({Key? key}) : super(key: key);

  @override
  _SiteSettingsScreenState createState() => _SiteSettingsScreenState();
}

class _SiteSettingsScreenState extends State<SiteSettingsScreen> {
  bool _sfwEnabled = true;

  @override
  void initState() {
    super.initState();
    _loadSfwEnabled();
  }

  Future<void> _loadSfwEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _sfwEnabled = prefs.getBool('sfwEnabled') ?? true;
    });
  }

  Future<void> _saveSfwEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('sfwEnabled', _sfwEnabled);
  }

  Future<void> _showNsfwConfirmationDialog() async {
    bool currentSfw = _sfwEnabled;
    String targetMode = currentSfw ? "NSFW" : "SFW";
    Color yesColor = currentSfw ? Colors.red : Colors.green;
    String dialogMessage = "Are you sure you want to enable $targetMode mode?";

    final result = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text("Confirm Mode Switch"),
          content: Text(dialogMessage),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              style: TextButton.styleFrom(backgroundColor: Colors.white),
              child: const Text("No", style: TextStyle(color: Colors.black)),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
              style: TextButton.styleFrom(backgroundColor: Colors.white),
              child: Text("Yes", style: TextStyle(color: yesColor)),
            ),
          ],
        );
      },
    );

    if (result == true) {
      setState(() {
        _sfwEnabled = !currentSfw;
      });
      await _saveSfwEnabled();
      Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Site Settings'),
      ),
      body: Center(
        child: Text(
          'Coming soon',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
        ),
      ),
    );
  }

}
