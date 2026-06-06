import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher_string.dart';

class NativeTranslateLauncher {
  const NativeTranslateLauncher._();

  static const MethodChannel _translationChannel =
      MethodChannel('app.translation');

  static Future<void> open(
    String text, {
    required String targetLanguageCode,
  }) async {
    final normalizedText = text.trim();
    if (normalizedText.isEmpty) return;

    if (Platform.isAndroid) {
      try {
        final shownProcessText = await _translationChannel.invokeMethod<bool>(
              'translation.showProcessText',
              {'text': normalizedText},
            ) ??
            false;
        if (shownProcessText) {
          return;
        }
        debugPrint(
          'NativeTranslateLauncher: PROCESS_TEXT translator unavailable, falling back to app/web translation.',
        );
      } catch (error) {
        debugPrint(
          'NativeTranslateLauncher: PROCESS_TEXT translation failed: $error',
        );
      }
    }

    if (Platform.isIOS) {
      try {
        final shownNativeSheet = await _translationChannel.invokeMethod<bool>(
              'translation.showNativeSheet',
              {'text': normalizedText},
            ) ??
            false;
        if (shownNativeSheet) {
          return;
        }
        debugPrint(
          'NativeTranslateLauncher: native translation sheet unavailable, falling back to app/web translation.',
        );
      } catch (error) {
        debugPrint(
          'NativeTranslateLauncher: native translation sheet failed: $error',
        );
      }
    }

    final targetLanguage = targetLanguageCode.trim().isNotEmpty
        ? targetLanguageCode.trim()
        : 'en';
    final encodedText = Uri.encodeQueryComponent(normalizedText);
    final appUrls = Platform.isAndroid
        ? const <String>[]
        : <String>[
            'googletranslate://?sl=auto&tl=$targetLanguage&text=$encodedText',
            'comgoogletranslate://?sl=auto&tl=$targetLanguage&text=$encodedText',
          ];
    final webUrl =
        'https://translate.google.com/?sl=auto&tl=$targetLanguage&text=$encodedText&op=translate';

    for (final appUrl in appUrls) {
      try {
        final launchedApp = await launchUrlString(
          appUrl,
          mode: LaunchMode.externalNonBrowserApplication,
        );
        if (launchedApp) return;
      } catch (_) {}
    }

    await launchUrlString(
      webUrl,
      mode: LaunchMode.externalApplication,
    );
  }
}
