import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../main.dart'; // navigatorKey
import '../providers/NotificationNavigationProvider.dart';
import 'notes_refresh_service.dart';
import 'notification_refresh_service.dart';

Future<void> processPendingNavigation({String from = 'unknown'}) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  final payload = prefs.getString('pending_navigation');

  if (payload == null) {
    debugPrint('[PENDING_NAV] nothing to process (from=$from)');
    return;
  }

  final ctx = navigatorKey.currentContext;
  debugPrint('[PENDING_NAV] handling "$payload" (from=$from) ctx=${ctx != null}');

  if (ctx != null) {
    final navProvider = Provider.of<NotificationNavigationProvider>(ctx, listen: false);
    final bool isNotes = payload.startsWith('note_') || payload.contains('DrawerIndex.Notes');

    // 1) Switch tab now
    navProvider.setTargetIndex(isNotes ? 4 : 3);

    // 2) Trigger refresh on the next frame (after tab is mounted)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (isNotes) {
        NotesRefreshService().triggerRefresh();
        debugPrint('NOTES REFRESH TRIGGERED_postframe ($from)');
      } else {
        NotificationRefreshService().triggerRefresh();
        debugPrint('ACTIVITIES REFRESH TRIGGERED_postframe ($from)');
      }
    });
  }

  // Clear the pending flag either way
  await prefs.remove('pending_navigation');
}
