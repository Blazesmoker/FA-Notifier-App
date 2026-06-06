import 'dart:async';
import 'dart:io';

import 'package:FANotifier/features/settings/data/translator_settings_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_language_id/google_mlkit_language_id.dart';
import 'package:html/parser.dart' as html_parser;

class TranslationService {
  TranslationService._();

  static final TranslationService instance = TranslationService._();

  final Map<String, String> _languageDetectionCache = <String, String>{};
  final Map<String, List<VoidCallback>> _languageDetectionCallbacks =
      <String, List<VoidCallback>>{};
  final Set<String> _languageDetectionInFlight = <String>{};
  final LanguageIdentifier _languageIdentifier = LanguageIdentifier(
    confidenceThreshold: 0.5,
  );

  String plainTextFromHtml(String html) {
    final document = html_parser.parse(html);
    return document.body?.text.trim() ?? '';
  }

  bool shouldOfferTranslation(
    String text,
    TranslatorSettingsProvider settings, {
    VoidCallback? onLanguageDetectionUpdated,
  }) {
    if (!settings.enabled) return false;
    switch (settings.buttonMode) {
      case TranslatorButtonMode.always:
        return text.trim().isNotEmpty;
      case TranslatorButtonMode.auto:
        return looksForeignToTargets(
          text,
          settings.targetLanguageCodes,
          onLanguageDetectionUpdated: onLanguageDetectionUpdated,
        );
      case TranslatorButtonMode.off:
        return false;
    }
  }

  bool looksForeignToTargets(
    String text,
    Set<String> targetLanguageCodes, {
    VoidCallback? onLanguageDetectionUpdated,
  }) {
    final normalizedText = text.trim();
    if (normalizedText.isEmpty) return false;

    final targets = targetLanguageCodes.map(_normalizeLanguageCode).toSet();
    final scriptDecision =
        _scriptBasedForeignDecisionForTargets(normalizedText, targets);
    if (scriptDecision != null) return scriptDecision;

    final cacheKey = _languageDetectionKey(normalizedText);
    final detectedLanguage = _languageDetectionCache[cacheKey];
    if (detectedLanguage != null) {
      return _detectedLanguageLooksForeign(detectedLanguage, targets);
    }

    if (onLanguageDetectionUpdated != null) {
      _queueLanguageDetection(normalizedText, onLanguageDetectionUpdated);
    }

    return false;
  }

  bool? _scriptBasedForeignDecisionForTargets(
    String normalizedText,
    Set<String> targets,
  ) {
    var hasUnknownDecision = false;
    for (final target in targets) {
      final decision = _scriptBasedForeignDecision(normalizedText, target);
      if (decision == false) return false;
      if (decision == null) hasUnknownDecision = true;
    }
    return hasUnknownDecision ? null : true;
  }

  bool? _scriptBasedForeignDecision(String normalizedText, String target) {
    final hasCyrillic = RegExp(r'[\u0400-\u04FF]').hasMatch(normalizedText);
    final hasLatinWord =
        RegExp(r'\b[A-Za-z][A-Za-z]{2,}\b').hasMatch(normalizedText);
    final hasGreek = RegExp(r'[\u0370-\u03FF]').hasMatch(normalizedText);
    final hasCjk = RegExp(r'[\u3040-\u30FF\u3400-\u9FFF\uAC00-\uD7AF]')
        .hasMatch(normalizedText);
    final hasArabic = RegExp(r'[\u0600-\u06FF]').hasMatch(normalizedText);
    final hasHebrew = RegExp(r'[\u0590-\u05FF]').hasMatch(normalizedText);
    final hasDevanagari = RegExp(r'[\u0900-\u097F]').hasMatch(normalizedText);

    if (target == 'ru' || target == 'uk' || target == 'bg') {
      return hasLatinWord || hasGreek || hasCjk || hasArabic || hasHebrew;
    }
    if (target == 'ja' || target == 'zh' || target == 'ko') {
      return hasLatinWord || hasCyrillic || hasGreek || hasArabic || hasHebrew;
    }
    if (target == 'ar') {
      return hasLatinWord || hasCyrillic || hasGreek || hasCjk || hasHebrew;
    }
    if (target == 'he') {
      return hasLatinWord || hasCyrillic || hasGreek || hasCjk || hasArabic;
    }
    if (target == 'hi') {
      return hasLatinWord ||
          hasCyrillic ||
          hasGreek ||
          hasCjk ||
          hasArabic ||
          hasHebrew;
    }

    final hasForeignScript = hasCyrillic ||
        hasGreek ||
        hasCjk ||
        hasArabic ||
        hasHebrew ||
        hasDevanagari;
    if (hasForeignScript) return true;
    if (hasLatinWord) return null;
    return false;
  }

  bool _detectedLanguageLooksForeign(
    String detectedLanguage,
    Set<String> targetLanguageCodes,
  ) {
    final detected = _normalizeLanguageCode(detectedLanguage);
    if (detected.isEmpty || detected == 'und') return false;
    return !targetLanguageCodes.contains(detected);
  }

  void _queueLanguageDetection(String text, VoidCallback callback) {
    final cacheKey = _languageDetectionKey(text);
    if (_languageDetectionCache.containsKey(cacheKey)) return;
    _languageDetectionCallbacks
        .putIfAbsent(cacheKey, () => <VoidCallback>[])
        .add(callback);
    if (!_languageDetectionInFlight.add(cacheKey)) return;

    unawaited(
      _identifyLanguage(text).whenComplete(() {
        _languageDetectionInFlight.remove(cacheKey);
        final callbacks =
            _languageDetectionCallbacks.remove(cacheKey) ?? <VoidCallback>[];
        for (final queuedCallback in callbacks) {
          queuedCallback();
        }
      }),
    );
  }

  Future<String?> _identifyLanguage(String text) async {
    final normalizedText = text.trim();
    if (normalizedText.isEmpty) return null;

    final cacheKey = _languageDetectionKey(normalizedText);
    final cached = _languageDetectionCache[cacheKey];
    if (cached != null) return cached;

    if (!Platform.isAndroid && !Platform.isIOS) {
      _languageDetectionCache[cacheKey] = 'und';
      return 'und';
    }

    try {
      final detected = await _languageIdentifier.identifyLanguage(
        normalizedText,
      );
      final normalizedDetected = _normalizeLanguageCode(detected);
      _languageDetectionCache[cacheKey] = normalizedDetected;
      return normalizedDetected;
    } catch (_) {
      _languageDetectionCache[cacheKey] = 'und';
      return 'und';
    }
  }

  String _languageDetectionKey(String text) {
    return text.trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  String _normalizeLanguageCode(String code) {
    final normalized = code.trim().replaceAll('_', '-').toLowerCase();
    final dashIndex = normalized.indexOf('-');
    return dashIndex == -1 ? normalized : normalized.substring(0, dashIndex);
  }
}
