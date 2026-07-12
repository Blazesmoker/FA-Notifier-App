import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';

import 'package:FANotifier/app/navigation/app_navigation.dart';
import 'package:FANotifier/core/logging/app_logging.dart';
import 'package:FANotifier/features/notes/data/notes_refresh_service.dart';
import 'package:FANotifier/features/notifications/data/notification_refresh_service.dart';
import 'package:FANotifier/features/notifications/data/pending_navigation_store.dart';
import 'package:FANotifier/features/notifications/domain/notification_payloads.dart';
import 'package:FANotifier/features/notifications/presentation/notification_navigation_provider.dart';

final AppNotificationNavigation appNotificationNavigation =
    AppNotificationNavigation();

class AppNotificationNavigation {
  AppNotificationNavigation({PendingNavigationStore? pendingNavigationStore})
      : _pendingNavigationStore =
            pendingNavigationStore ?? const PendingNavigationStore();

  final PendingNavigationStore _pendingNavigationStore;
  static const Duration _duplicateTapWindow = Duration(seconds: 1);
  String? _lastNavigationPayload;
  DateTime? _lastNavigationAt;

  Future<void> handleTap(String payload, String source) async {
    final context = navigatorKey.currentContext;
    if (context == null) {
      await _pendingNavigationStore.savePayload(payload);
      appLog('[NOTIF] No UI context; saved pending navigation.');
      kDebugPrint('[NOTIF] No UI context; saved pending_navigation="$payload"');
      return;
    }
    if (!_claimNavigation(payload)) {
      appLog('[NOTIF] Ignored duplicate navigation payload.');
      return;
    }

    navigatorKey.currentState?.popUntil((route) => route.isFirst);
    await _pendingNavigationStore.clearPayload();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 16));
      final currentContext = navigatorKey.currentContext;
      if (currentContext == null) {
        _releaseNavigation(payload);
        await _pendingNavigationStore.savePayload(payload);
        appLog(
          '[NOTIF] Lost context after frame; re-stashed pending navigation.',
        );
        return;
      }

      final navigationProvider =
          Provider.of<NotificationNavigationProvider>(
        currentContext,
        listen: false,
      );
      final isNotes = isNoteNotificationPayload(payload);
      navigationProvider.setTargetIndex(isNotes ? 4 : 3);

      try {
        if (isNotes) {
          NotesRefreshService().triggerRefresh();
          appLog('[NOTIF] Notes refresh triggered.');
        } else {
          NotificationRefreshService().triggerRefresh();
          appLog('[NOTIF] Activities refresh triggered.');
        }
      } catch (error) {
        appLog('[AppNotificationNavigation.handleTap] refresh error: $error');
      }

      await _pendingNavigationStore.recordHandledPayload(payload);
    });

    SchedulerBinding.instance.ensureVisualUpdate();
  }

  Future<void> processPending({String from = 'unknown'}) async {
    final payload =
        await _pendingNavigationStore.loadPayload(reload: true);
    if (payload == null) {
      debugPrint('[PENDING_NAV] nothing to process (from=$from)');
      return;
    }
    if (payload.isEmpty) {
      debugPrint('[PENDING_NAV] empty payload; clearing (from=$from)');
      await _pendingNavigationStore.clearPayload();
      return;
    }
    if (payload == appUpdateNotificationPayload) {
      await _pendingNavigationStore.clearPayload();
      return;
    }

    final context = navigatorKey.currentContext;
    debugPrint(
      '[PENDING_NAV] handling "$payload" (from=$from) ctx=${context != null}',
    );
    if (context == null) {
      debugPrint(
        '[PENDING_NAV] no context yet; will retry next frame (from=$from)',
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        processPending(from: '$from/retry');
      });
      SchedulerBinding.instance.ensureVisualUpdate();
      return;
    }

    final navigationProvider =
        Provider.of<NotificationNavigationProvider>(context, listen: false);
    if (!navigationProvider.hasNavigationListeners) {
      debugPrint(
        '[PENDING_NAV] navProvider has no listeners; keeping pending (from=$from)',
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        processPending(from: '$from/retry_listeners');
      });
      SchedulerBinding.instance.ensureVisualUpdate();
      return;
    }
    if (!_claimNavigation(payload)) {
      debugPrint(
        '[PENDING_NAV] duplicate payload ignored (from=$from)',
      );
      await _pendingNavigationStore.clearPayload();
      return;
    }

    final isNotes = isNoteNotificationPayload(payload);
    navigationProvider.setTargetIndex(isNotes ? 4 : 3);

    try {
      if (isNotes) {
        NotesRefreshService().triggerRefresh();
        debugPrint('NOTES REFRESH TRIGGERED_pending_nav ($from)');
      } else {
        NotificationRefreshService().triggerRefresh();
        debugPrint('ACTIVITIES REFRESH TRIGGERED_pending_nav ($from)');
      }
    } catch (error) {
      debugPrint('[PENDING_NAV] refresh error: $error');
    }

    await _pendingNavigationStore.clearPayload();
  }

  bool _claimNavigation(String payload) {
    final now = DateTime.now();
    final lastNavigationAt = _lastNavigationAt;
    if (_lastNavigationPayload == payload && lastNavigationAt != null) {
      final elapsed = now.difference(lastNavigationAt);
      if (!elapsed.isNegative && elapsed < _duplicateTapWindow) {
        return false;
      }
    }
    _lastNavigationPayload = payload;
    _lastNavigationAt = now;
    return true;
  }

  void _releaseNavigation(String payload) {
    if (_lastNavigationPayload != payload) return;
    _lastNavigationPayload = null;
    _lastNavigationAt = null;
  }
}
