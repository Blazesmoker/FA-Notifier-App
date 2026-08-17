import 'package:material_ui/material_ui.dart';

import 'package:fanotifier/core/analytics/app_analytics.dart';

final RouteObserver<ModalRoute<dynamic>> routeObserver =
    RouteObserver<ModalRoute<dynamic>>();
final AppAnalyticsRouteObserver analyticsRouteObserver =
    AppAnalyticsRouteObserver();
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<ScaffoldMessengerState> rootMessengerKey =
    GlobalKey<ScaffoldMessengerState>();
