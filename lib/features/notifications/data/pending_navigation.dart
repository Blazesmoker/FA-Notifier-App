import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:FANotifier/main.dart'; // navigatorKey
import 'package:FANotifier/features/notifications/presentation/NotificationNavigationProvider.dart';
import 'package:FANotifier/features/notes/data/notes_refresh_service.dart';
import 'package:FANotifier/features/notifications/data/notification_refresh_service.dart';

Future<void> processPendingNavigation({String from = 'unknown'}) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  final payload = prefs.getString('pending_navigation');

  if (payload == null) {
    debugPrint('[PENDING_NAV] nothing to process (from=$from)');
    return;
  }

  if (payload.isEmpty) {
    debugPrint('[PENDING_NAV] empty payload; clearing (from=$from)');
    await prefs.remove('pending_navigation');
    return;
  }

  final ctx = navigatorKey.currentContext;
  debugPrint('[PENDING_NAV] handling "$payload" (from=$from) ctx=${ctx != null}');

  if (ctx == null) {
    // Keep pending payload; UI isn't ready yet. Retry once next frame.
    debugPrint('[PENDING_NAV] no context yet; will retry next frame (from=$from)');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      processPendingNavigation(from: '$from/retry');
    });
    SchedulerBinding.instance.ensureVisualUpdate();
    return;
  }

  final navProvider =
      Provider.of<NotificationNavigationProvider>(ctx, listen: false);

  // If nobody is listening yet, don't clear the payload; let HomeScreen/lifecycle
  // pick it up once mounted.
  if (!navProvider.hasListeners) {
    debugPrint('[PENDING_NAV] navProvider has no listeners; keeping pending (from=$from)');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      processPendingNavigation(from: '$from/retry_listeners');
    });
    SchedulerBinding.instance.ensureVisualUpdate();
    return;
  }

  final bool isNotes = payload.startsWith('note_') ||
      payload.contains('DrawerIndex.Notes') ||
      payload == 'note_native';

  // Switch tab now (Notes=4, Notifications=3).
  navProvider.setTargetIndex(isNotes ? 4 : 3);

  // Refresh immediately. Notes/Notifications screens are kept alive in
  // HomeScreen's `IndexedStack`, so listeners are already attached.
  try {
    if (isNotes) {
      NotesRefreshService().triggerRefresh();
      debugPrint('NOTES REFRESH TRIGGERED_pending_nav ($from)');
    } else {
      NotificationRefreshService().triggerRefresh();
      debugPrint('ACTIVITIES REFRESH TRIGGERED_pending_nav ($from)');
    }
  } catch (e) {
    debugPrint('[PENDING_NAV] refresh error: $e');
  }

  // Clear only after successfully handling.
  await prefs.remove('pending_navigation');
}
