import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

class IOSActivityNotificationLock {
  static const MethodChannel _channel = MethodChannel('app.background_fetch');
  static final Object _zoneKey = Object();

  static Future<T> synchronized<T>(
    Future<T> Function() operation, {
    bool Function()? isCancelled,
  }) async {
    if (!Platform.isIOS || Zone.current[_zoneKey] == true) {
      return operation();
    }
    String? token;
    while (token == null) {
      if (isCancelled?.call() ?? false) {
        throw StateError('Activity state operation cancelled');
      }
      token = await _channel.invokeMethod<String>('acquireActivityState');
      if (token == null) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }
    try {
      if (isCancelled?.call() ?? false) {
        throw StateError('Activity state operation cancelled');
      }
      return await runZoned(operation, zoneValues: <Object, Object>{
        _zoneKey: true,
      });
    } finally {
      await _channel.invokeMethod<void>('releaseActivityState', token);
    }
  }
}
