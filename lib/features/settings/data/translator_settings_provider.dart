import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TranslatorLanguageOption {
  const TranslatorLanguageOption(this.code, this.label);

  final String code;
  final String label;
}

enum TranslatorButtonMode {
  always,
  auto,
  off,
}

const List<TranslatorLanguageOption> translatorLanguageOptions = [
  TranslatorLanguageOption('en', 'English'),
  TranslatorLanguageOption('ru', 'Russian'),
  TranslatorLanguageOption('es', 'Spanish'),
  TranslatorLanguageOption('fr', 'French'),
  TranslatorLanguageOption('de', 'German'),
  TranslatorLanguageOption('it', 'Italian'),
  TranslatorLanguageOption('pt', 'Portuguese'),
  TranslatorLanguageOption('pl', 'Polish'),
  TranslatorLanguageOption('uk', 'Ukrainian'),
  TranslatorLanguageOption('tr', 'Turkish'),
  TranslatorLanguageOption('ja', 'Japanese'),
  TranslatorLanguageOption('ko', 'Korean'),
  TranslatorLanguageOption('zh', 'Chinese'),
  TranslatorLanguageOption('ar', 'Arabic'),
  TranslatorLanguageOption('hi', 'Hindi'),
  TranslatorLanguageOption('id', 'Indonesian'),
  TranslatorLanguageOption('vi', 'Vietnamese'),
  TranslatorLanguageOption('nl', 'Dutch'),
  TranslatorLanguageOption('sv', 'Swedish'),
  TranslatorLanguageOption('fi', 'Finnish'),
  TranslatorLanguageOption('cs', 'Czech'),
  TranslatorLanguageOption('da', 'Danish'),
  TranslatorLanguageOption('el', 'Greek'),
  TranslatorLanguageOption('he', 'Hebrew'),
  TranslatorLanguageOption('ro', 'Romanian'),
];

class TranslatorSettingsProvider with ChangeNotifier {
  static const String _enabledKey = 'translator_enabled';
  static const String _targetLanguageCodeKey = 'translator_target_language_code';
  static const String _targetLanguageCodesKey = 'translator_target_language_codes';
  static const String _buttonModeKey = 'translator_button_mode';

  bool _enabled = true;
  TranslatorButtonMode _buttonMode = TranslatorButtonMode.auto;
  Set<String> _targetLanguageCodes = <String>{};
  bool _loaded = false;

  TranslatorSettingsProvider() {
    load();
  }

  bool get enabled => _enabled;
  TranslatorButtonMode get buttonMode => _buttonMode;
  bool get loaded => _loaded;

  String get systemLanguageCode {
    final locale = WidgetsBinding.instance.platformDispatcher.locale;
    final code = locale.languageCode.trim().toLowerCase();
    return code.isEmpty ? 'en' : _normalizeLanguageCode(code);
  }

  String get targetLanguageCode {
    if (_targetLanguageCodes.isEmpty ||
        _targetLanguageCodes.contains(systemLanguageCode)) {
      return systemLanguageCode;
    }
    return _targetLanguageCodes.first;
  }

  Set<String> get targetLanguageCodes {
    if (_targetLanguageCodes.isEmpty) {
      return <String>{systemLanguageCode};
    }
    return Set<String>.unmodifiable(_targetLanguageCodes);
  }

  String get targetLanguagesLabel {
    final codes = targetLanguageCodes;
    if (codes.length == 1) {
      return languageLabelForCode(codes.first);
    }
    return '${codes.length} selected';
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(_enabledKey) ?? true;
    _buttonMode = _buttonModeFromString(
      prefs.getString(_buttonModeKey),
      legacyShowButtonsAutomatically:
          prefs.getBool('translator_show_buttons_automatically'),
    );
    if (_buttonMode == TranslatorButtonMode.off) {
      _enabled = false;
    } else if (!_enabled) {
      _buttonMode = TranslatorButtonMode.off;
    }
    final savedTargetLanguages = prefs.getStringList(_targetLanguageCodesKey);
    final legacyTargetLanguage = prefs.getString(_targetLanguageCodeKey);
    final loadedTargets = savedTargetLanguages ??
        (legacyTargetLanguage == null || legacyTargetLanguage.trim().isEmpty
            ? <String>[systemLanguageCode]
            : <String>[legacyTargetLanguage]);
    _targetLanguageCodes = loadedTargets
        .map(_normalizeLanguageCode)
        .where((code) => code.isNotEmpty)
        .toSet();
    if (_targetLanguageCodes.isEmpty) {
      _targetLanguageCodes = <String>{systemLanguageCode};
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> setEnabled(bool value) async {
    if (_enabled == value && (value || _buttonMode == TranslatorButtonMode.off)) {
      return;
    }
    _enabled = value;
    if (value && _buttonMode == TranslatorButtonMode.off) {
      _buttonMode = TranslatorButtonMode.auto;
    } else if (!value) {
      _buttonMode = TranslatorButtonMode.off;
    }
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, value);
    await prefs.setString(_buttonModeKey, _buttonMode.name);
  }

  Future<void> setButtonMode(TranslatorButtonMode value) async {
    final nextEnabled = value != TranslatorButtonMode.off;
    if (_buttonMode == value && _enabled == nextEnabled) return;
    _buttonMode = value;
    _enabled = nextEnabled;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_buttonModeKey, value.name);
    await prefs.setBool(_enabledKey, _enabled);
  }

  Future<void> setTargetLanguageCodes(Iterable<String> values) async {
    final nextValues = values
        .map(_normalizeLanguageCode)
        .where((code) => code.isNotEmpty)
        .toSet();
    if (nextValues.isEmpty || setEquals(_targetLanguageCodes, nextValues)) {
      return;
    }
    _targetLanguageCodes = nextValues;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_targetLanguageCodesKey, nextValues.toList());
    await prefs.remove(_targetLanguageCodeKey);
  }

  static String languageLabelForCode(String code) {
    final normalized = _normalizeLanguageCode(code);
    for (final option in translatorLanguageOptions) {
      if (option.code == normalized) return option.label;
    }
    return normalized.toUpperCase();
  }

  static String _normalizeLanguageCode(String code) {
    final normalized = code.trim().replaceAll('_', '-').toLowerCase();
    final dashIndex = normalized.indexOf('-');
    return dashIndex == -1 ? normalized : normalized.substring(0, dashIndex);
  }

  static TranslatorButtonMode _buttonModeFromString(
    String? value, {
    bool? legacyShowButtonsAutomatically,
  }) {
    switch (value) {
      case 'always':
        return TranslatorButtonMode.always;
      case 'off':
        return TranslatorButtonMode.off;
      case 'auto':
        return TranslatorButtonMode.auto;
    }
    if (legacyShowButtonsAutomatically == false) {
      return TranslatorButtonMode.always;
    }
    return TranslatorButtonMode.auto;
  }
}
