import 'package:firebase_analytics/firebase_analytics.dart';

import 'package:fanotifier/core/analytics/app_analytics.dart';

final FirebaseAnalytics analytics = FirebaseAnalytics.instance;

Future<void> setupAnalyticsPrivacy({required bool analyticsEnabled}) async {
  await appAnalytics.applyPrivacyConsent(analyticsEnabled);
  await analytics.setDefaultEventParameters(null);
  await analytics.setUserId(id: null);
  await appAnalytics.configureAnonymousDeviceProperties();
}
