import 'package:FANotifier/features/settings/data/translator_settings_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class TranslatorSettingsScreen extends StatelessWidget {
  const TranslatorSettingsScreen({super.key});

  Future<void> _showTargetLanguages(
    BuildContext context,
    TranslatorSettingsProvider settings,
  ) async {
    final selectedLanguages = settings.targetLanguageCodes.toSet();
    final availableLanguages = translatorLanguageOptions.toList();
    for (final code in selectedLanguages) {
      if (!availableLanguages.any((option) => option.code == code)) {
        availableLanguages.add(
          TranslatorLanguageOption(
            code,
            TranslatorSettingsProvider.languageLabelForCode(code),
          ),
        );
      }
    }
    final result = await showDialog<Set<String>>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Target Languages'),
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
              content: SizedBox(
                width: double.maxFinite,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: availableLanguages.length,
                  itemBuilder: (context, index) {
                    final option = availableLanguages[index];
                    final selected = selectedLanguages.contains(option.code);
                    return ListTile(
                      title: Text(option.label),
                      trailing: selected
                          ? const Icon(
                              Icons.check,
                              color: Color(0xFFE09321),
                            )
                          : null,
                      onTap: () {
                        if (selected && selectedLanguages.length == 1) return;
                        setDialogState(() {
                          if (selected) {
                            selectedLanguages.remove(option.code);
                          } else {
                            selectedLanguages.add(option.code);
                          }
                        });
                      },
                    );
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, selectedLanguages),
                  child: const Text('Done'),
                ),
              ],
            );
          },
        );
      },
    );
    if (result != null) {
      await settings.setTargetLanguageCodes(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<TranslatorSettingsProvider>();
    final controlsEnabled = settings.enabled;

    return Scaffold(
      appBar: AppBar(title: const Text('Translator Settings')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 8.0),
        children: [
          const SizedBox(height: 8),
          SwitchListTile(
            activeThumbColor: const Color(0xFFE09321),
            secondary: const Icon(Icons.g_translate, color: Color(0xFFE09321)),
            title: const Text('Translator'),
            value: settings.enabled,
            onChanged: settings.setEnabled,
          ),
          const Divider(
            height: 1.0,
            color: Color(0xFF111111),
            thickness: 3.0,
          ),
          ListTile(
            enabled: controlsEnabled,
            leading: Icon(
              Icons.language,
              color: controlsEnabled ? const Color(0xFFE09321) : Colors.grey,
            ),
            title: const Text('Target Languages'),
            trailing: Text(
              settings.targetLanguagesLabel,
              style: TextStyle(
                color: controlsEnabled ? Colors.white70 : Colors.grey,
              ),
            ),
            onTap: controlsEnabled
                ? () => _showTargetLanguages(context, settings)
                : null,
          ),
          const Divider(
            height: 1.0,
            color: Color(0xFF111111),
            thickness: 3.0,
          ),
          ListTile(
            enabled: controlsEnabled,
            leading: Icon(
              Icons.visibility,
              color: controlsEnabled ? const Color(0xFFE09321) : Colors.grey,
            ),
            title: const Text('Show Buttons'),
            trailing: DropdownButtonHideUnderline(
              child: DropdownButton<TranslatorButtonMode>(
                value: settings.buttonMode,
                dropdownColor: const Color(0xFF1B1B1B),
                items: const [
                  DropdownMenuItem<TranslatorButtonMode>(
                    value: TranslatorButtonMode.always,
                    child: Text('Always On'),
                  ),
                  DropdownMenuItem<TranslatorButtonMode>(
                    value: TranslatorButtonMode.auto,
                    child: Text('Auto'),
                  ),
                  DropdownMenuItem<TranslatorButtonMode>(
                    value: TranslatorButtonMode.off,
                    child: Text('Off'),
                  ),
                ],
                onChanged: controlsEnabled
                    ? (value) {
                        if (value != null) {
                          settings.setButtonMode(value);
                        }
                      }
                    : null,
              ),
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
