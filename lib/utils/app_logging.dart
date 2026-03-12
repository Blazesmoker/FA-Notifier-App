import 'package:flutter/foundation.dart';

void configureAppLogging() {
  if (!kDebugMode) {
    debugPrint = _noopDebugPrint;
  }
}

void kDebugPrint(String? message, {int? wrapWidth}) {
  if (kDebugMode) {
    debugPrint(message, wrapWidth: wrapWidth);
  }
}

void appLog(String? message, {int? wrapWidth}) {
  debugPrintSynchronously(message, wrapWidth: wrapWidth);
}

void _noopDebugPrint(String? message, {int? wrapWidth}) {}
