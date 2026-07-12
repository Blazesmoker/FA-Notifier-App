import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';

class BackgroundWorkmanagerInitializer {
  BackgroundWorkmanagerInitializer({required void Function() callbackDispatcher})
      : _callbackDispatcher = callbackDispatcher;

  final void Function() _callbackDispatcher;
  bool _initialized = false;

  Future<void> ensureWorkmanagerInitialized() async {
    if (_initialized) return;
    debugPrint("Initializing Workmanager...");
    await Workmanager().initialize(_callbackDispatcher);
    _initialized = true;
    debugPrint("Workmanager initialized");
  }
}
