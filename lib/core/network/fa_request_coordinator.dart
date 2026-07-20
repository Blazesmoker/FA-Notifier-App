import 'dart:async';
import 'dart:io' as io;
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'package:fanotifier/core/fa/fa_cookie_helper.dart';

enum FaRequestCoordinatorState {
  normal,
  waitingToRetry,
  maintenanceOrUnavailable,
}

class FaRequestSnapshot {
  const FaRequestSnapshot({
    required this.state,
    this.allowedAt,
    this.message,
  });

  final FaRequestCoordinatorState state;
  final DateTime? allowedAt;
  final String? message;

  Duration get remaining {
    final waitUntil = allowedAt;
    if (waitUntil == null) return Duration.zero;
    final remaining = waitUntil.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }
}

class FaRequestCoordinator {
  FaRequestCoordinator._();

  static final FaRequestCoordinator instance = FaRequestCoordinator._();
  static const Duration minRequestSpacing = Duration(seconds: 1);

  final ValueNotifier<FaRequestSnapshot> status =
      ValueNotifier<FaRequestSnapshot>(
    const FaRequestSnapshot(state: FaRequestCoordinatorState.normal),
  );

  Future<void> _queue = Future<void>.value();
  DateTime _nextRequestAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime? _blockedUntil;
  String? _blockedMessage;
  int _recoverableFailureCount = 0;
  int _unavailableFailureCount = 0;
  int _http503FailureCount = 0;
  int _requestSequence = 0;

  Future<void> waitForTurn({String? label}) {
    final id = ++_requestSequence;
    final requestedAt = DateTime.now();
    final requestLabel = label ?? 'FA request';
    final next = _queue.catchError((_) {}).then((_) async {
      final now = DateTime.now();
      final queueDelay = now.difference(requestedAt);
      var allowedAt = _nextRequestAt;
      final blockedUntil = _blockedUntil;
      if (blockedUntil != null && blockedUntil.isAfter(allowedAt)) {
        allowedAt = blockedUntil;
      }
      if (allowedAt.isAfter(now)) {
        final wait = allowedAt.difference(now);
        if (kDebugMode) {
          debugPrint(
            '[FA request gate] #$id $requestLabel queued ${queueDelay.inMilliseconds}ms, waiting ${wait.inMilliseconds}ms',
          );
        }
        _setStatus(
          FaRequestSnapshot(
            state: FaRequestCoordinatorState.waitingToRetry,
            allowedAt: allowedAt,
            message: _blockedMessage,
          ),
        );
        await Future.delayed(allowedAt.difference(now));
        if (kDebugMode) {
          debugPrint(
            '[FA request gate] #$id $requestLabel starting after ${DateTime.now().difference(requestedAt).inMilliseconds}ms total',
          );
        }
      } else {
        if (kDebugMode) {
          debugPrint(
            '[FA request gate] #$id $requestLabel starting immediately after ${queueDelay.inMilliseconds}ms queued',
          );
        }
      }
      _nextRequestAt = DateTime.now().add(minRequestSpacing);
      if (_blockedUntil != null &&
          !_blockedUntil!.isAfter(DateTime.now())) {
        _blockedUntil = null;
        _blockedMessage = null;
        if (_recoverableFailureCount == 0) {
          _setStatus(
            const FaRequestSnapshot(state: FaRequestCoordinatorState.normal),
          );
        }
      }
    });
    _queue = next;
    return next;
  }

  void recordSuccess() {
    _recoverableFailureCount = 0;
    _unavailableFailureCount = 0;
    _http503FailureCount = 0;
    if (_blockedUntil == null || !_blockedUntil!.isAfter(DateTime.now())) {
      _blockedUntil = null;
      _blockedMessage = null;
      _setStatus(
        const FaRequestSnapshot(state: FaRequestCoordinatorState.normal),
      );
    }
  }

  void recordHttpStatus({
    required int? statusCode,
    Map<String, String>? headers,
    Object? responseBody,
  }) {
    if (statusCode == 429) {
      recordWait(
        retryAfter: parseRetryAfterHeader(_headerValue(headers, 'retry-after')) ??
            const Duration(seconds: 30),
        message: 'FA is asking FANotifier to wait before retrying.',
      );
      return;
    }

    if (statusCode == 403) {
      final body = responseBody?.toString() ?? '';
      if (body.isNotEmpty &&
          FaCookieHelper.isCloudflareChallengePage(
            body: body,
            statusCode: statusCode,
          )) {
        return;
      }
      recordMaintenanceOrUnavailable(
        message:
            'Fur Affinity returned HTTP 403 and is temporarily unavailable.',
      );
      return;
    }

    if (statusCode == 503) {
      recordHttp503();
      return;
    }

    if (statusCode != null && statusCode >= 200 && statusCode < 500) {
      recordSuccess();
    }
  }

  void recordHttp503() {
    _http503FailureCount++;
    final seconds = math.min<int>(
      300,
      5 * math.pow(2, _http503FailureCount - 1).toInt(),
    );
    recordWait(
      retryAfter: Duration(seconds: seconds),
      message: 'FA returned 503. Waiting before retrying.',
    );
  }

  void recordRecoverableFailure() {
    _recoverableFailureCount++;
    final seconds = math.min<int>(
      32,
      math.max<int>(2, math.pow(2, _recoverableFailureCount - 1).toInt()),
    );
    recordWait(
      retryAfter: Duration(seconds: seconds),
      message: 'Waiting before retrying FA.',
    );
  }

  void recordWait({
    required Duration retryAfter,
    String? message,
  }) {
    final allowedAt = DateTime.now().add(retryAfter);
    _blockedUntil = allowedAt;
    _blockedMessage = message;
    _setStatus(
      FaRequestSnapshot(
        state: FaRequestCoordinatorState.waitingToRetry,
        allowedAt: allowedAt,
        message: message,
      ),
    );
  }

  void recordMaintenanceOrUnavailable({
    required String message,
    Duration? retryAfter,
  }) {
    _unavailableFailureCount++;
    final delay = retryAfter ??
        Duration(
          seconds: math.min<int>(
            300,
            30 * math.pow(2, _unavailableFailureCount - 1).toInt(),
          ),
        );
    final allowedAt = DateTime.now().add(delay);
    _blockedUntil = allowedAt;
    _blockedMessage = message;
    _setStatus(
      FaRequestSnapshot(
        state: FaRequestCoordinatorState.maintenanceOrUnavailable,
        allowedAt: allowedAt,
        message: message,
      ),
    );
  }

  void _setStatus(FaRequestSnapshot next) {
    status.value = next;
  }
}

String? _headerValue(Map<String, String>? headers, String name) {
  if (headers == null) return null;
  final lowerName = name.toLowerCase();
  for (final entry in headers.entries) {
    if (entry.key.toLowerCase() == lowerName) {
      return entry.value;
    }
  }
  return null;
}

Duration? parseRetryAfterHeader(String? value) {
  if (value == null) return null;
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;

  final seconds = int.tryParse(trimmed);
  if (seconds != null && seconds > 0) {
    return Duration(seconds: seconds);
  }

  try {
    final date = io.HttpDate.parse(trimmed).toUtc();
    final remaining = date.difference(DateTime.now().toUtc());
    return remaining.isNegative ? null : remaining;
  } catch (_) {
    return null;
  }
}
