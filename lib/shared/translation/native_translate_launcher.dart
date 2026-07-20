import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:fanotifier/shared/translation/ios_scroll_recovery.dart';
import 'package:url_launcher/url_launcher_string.dart';

class NativeTranslateLauncher {
  const NativeTranslateLauncher._();

  static const MethodChannel _translationChannel =
      MethodChannel('app.translation');

  static Future<void> open(
    String text, {
    required String targetLanguageCode,
    IosScrollRecoveryScope? recoveryScope,
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
        final nativeSheetResult = await _translationChannel.invokeMethod(
          'translation.showNativeSheet',
          {'text': normalizedText},
        );
        final shownNativeSheet = _nativeSheetWasShown(nativeSheetResult);
        if (shownNativeSheet) {
          if (_nativeSheetRequiresScrollRecovery(nativeSheetResult)) {
            IosScrollRecovery.notifyTranslationSheetDismissed(
              scope: recoveryScope,
            );
          }
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

    final targetLanguage =
        targetLanguageCode.trim().isNotEmpty ? targetLanguageCode.trim() : 'en';
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

  static bool _nativeSheetWasShown(Object? result) {
    if (result is bool) return result;
    if (result is Map) return result['shown'] == true;
    return false;
  }

  static bool _nativeSheetRequiresScrollRecovery(Object? result) {
    if (result is Map) {
      return result['requiresScrollRecovery'] != false;
    }
    return true;
  }
}
