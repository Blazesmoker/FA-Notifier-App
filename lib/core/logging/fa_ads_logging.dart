import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:fanotifier/core/logging/app_logging.dart';

enum FaAdsLogCategory {
  config,
  cookie,
  http,
  delivery,
  visibility,
  slot,
  impression,
  click,
  lifecycle,
  perf,
  check,
}

class FaAdsLog {
  FaAdsLog._();

  static final Stopwatch _clock = Stopwatch()..start();
  static int _sequence = 0;
  static final Object _scopeKey = Object();

  static Future<T> scoped<T>(
    Future<T> Function() operation, {
    required int section,
    required int delivery,
    String? slot,
  }) {
    if (!kDebugMode) return operation();
    return runZoned(operation, zoneValues: {
      _scopeKey: _FaAdsLogScope(section, delivery, slot),
    });
  }

  static void event(
    FaAdsLogCategory category,
    String event, {
    int? section,
    int? delivery,
    String? slot,
    Map<String, num> counts = const {},
    Map<String, bool> checks = const {},
  }) {
    if (!kDebugMode) return;
    final scope = Zone.current[_scopeKey] as _FaAdsLogScope?;
    section ??= scope?.section;
    delivery ??= scope?.delivery;
    slot ??= scope?.slot;
    final fields = <String>[
      '#${++_sequence}',
      't=${_clock.elapsedMilliseconds}ms',
      if (section != null) 'section=$section',
      if (delivery != null) 'delivery=$delivery',
      if (slot != null) 'slot=$slot',
      for (final entry in counts.entries) '${entry.key}=${entry.value}',
      for (final entry in checks.entries) '${entry.key}=${entry.value}',
    ];
    kDebugPrint('[FAAds][${category.name.toUpperCase()}] $event ${fields.join(' ')}');
  }
}

class _FaAdsLogScope {
  const _FaAdsLogScope(this.section, this.delivery, this.slot);

  final int section;
  final int delivery;
  final String? slot;
}
