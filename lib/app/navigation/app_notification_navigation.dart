import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:fanotifier/app/navigation/app_navigation.dart';
import 'package:fanotifier/core/analytics/app_analytics.dart';
import 'package:fanotifier/core/logging/app_logging.dart';
import 'package:fanotifier/features/notes/domain/notes_refresh_port.dart';
import 'package:fanotifier/features/notes/notes_feature.dart';
import 'package:fanotifier/features/notifications/data/activities_notification_state.dart';
import 'package:fanotifier/features/notifications/domain/notification_payloads.dart';
import 'package:fanotifier/features/notifications/domain/notification_refresh_port.dart';
import 'package:fanotifier/features/notifications/domain/pending_navigation_repository.dart';
import 'package:fanotifier/features/notifications/notifications_feature.dart';
import 'package:fanotifier/features/notifications/presentation/notification_navigation_provider.dart';

final AppNotificationNavigation appNotificationNavigation =
    AppNotificationNavigation(
      pendingNavigationRepository:
          NotificationsFeature.createPendingNavigationRepository(),
      notesRefreshPort: NotesFeature.refreshPort,
      notificationRefreshPort: NotificationsFeature.refreshPort,
    );

class AppNotificationNavigation {
  AppNotificationNavigation({
    required this._pendingNavigationRepository,
    required this._notesRefreshPort,
    required this._notificationRefreshPort,
  });

  final PendingNavigationRepository _pendingNavigationRepository;
  final NotesRefreshPort _notesRefreshPort;
  final NotificationRefreshPort _notificationRefreshPort;
  static const Duration _duplicateTapWindow = Duration(seconds: 1);
  String? _lastNavigationPayload;
  DateTime? _lastNavigationAt;

  Future<void> handleTap(String payload, String source) async {
    await _pendingNavigationRepository.savePayload(payload);
    appLog('[NOTIF] Notification navigation queued (source=$source).');
    await processPending(from: 'tap:$source');
  }

  Future<void> processPending({String from = 'unknown'}) async {
    final payload =
        await _pendingNavigationRepository.loadPayload(reload: true);
    if (payload == null) {
      debugPrint('[PENDING_NAV] nothing to process (from=$from)');
      return;
    }
    if (payload.isEmpty) {
      debugPrint('[PENDING_NAV] empty payload; clearing (from=$from)');
      await _pendingNavigationRepository.clearPayload();
      return;
    }
    if (payload == appUpdateNotificationPayload) {
      await appAnalytics.logNotificationOpened(
        notificationType: 'update',
        executionContext: NotificationExecutionContext.backgroundPeriodic,
        openContext: from,
      );
      await _pendingNavigationRepository.clearPayload();
      return;
    }

    final context = navigatorKey.currentContext;
    final navigator = navigatorKey.currentState;
    debugPrint(
      '[PENDING_NAV] handling "$payload" (from=$from) ctx=${context != null}',
    );
    if (context == null || navigator == null) {
      debugPrint(
        '[PENDING_NAV] no context yet; keeping pending (from=$from)',
      );
      return;
    }
    if (!context.mounted) {
      debugPrint(
        '[PENDING_NAV] context is no longer mounted; keeping pending (from=$from)',
      );
      return;
    }

    final navigationProvider =
        Provider.of<NotificationNavigationProvider>(context, listen: false);
    if (!navigationProvider.hasNavigationListeners) {
      debugPrint(
        '[PENDING_NAV] navProvider has no listeners; keeping pending (from=$from)',
      );
      return;
    }
    if (!_claimNavigation(payload)) {
      debugPrint(
        '[PENDING_NAV] duplicate payload ignored (from=$from)',
      );
      await _pendingNavigationRepository.clearPayload();
      return;
    }

    final isNotes = isNoteNotificationPayload(payload);
    final isBackgroundActivity = payload.startsWith('fa_activity_');
    await appAnalytics.logNotificationOpened(
      notificationType: isNotes ? 'note' : 'activity',
      executionContext: isNotes || isBackgroundActivity
          ? NotificationExecutionContext.backgroundPeriodic
          : NotificationExecutionContext.foregroundImmediate,
      openContext: from,
    );

    navigator.popUntil((route) => route.isFirst);
    navigationProvider.setTargetIndex(isNotes ? 4 : 3);
    await _waitForNavigationFrame();

    try {
      if (isActivityNotificationPayload(payload)) {
        await ActivitiesNotificationStateStore()
            .acknowledgeLastShownCounts();
      }
      if (isNotes) {
        _notesRefreshPort.triggerRefresh();
        debugPrint('NOTES REFRESH TRIGGERED_pending_nav ($from)');
      } else {
        _notificationRefreshPort.triggerRefresh();
        debugPrint('ACTIVITIES REFRESH TRIGGERED_pending_nav ($from)');
      }
    } catch (error) {
      debugPrint('[PENDING_NAV] refresh error: $error');
    }

    await _pendingNavigationRepository.clearPayload();
    await _pendingNavigationRepository.recordHandledPayload(payload);
  }

  Future<void> _waitForNavigationFrame() {
    final completer = Completer<void>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      completer.complete();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
    return completer.future;
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
}
