import 'package:firebase_analytics/firebase_analytics.dart';

import 'package:fanotifier/core/analytics/app_analytics.dart';

final FirebaseAnalytics analytics = FirebaseAnalytics.instance;

Future<void> setupAnalyticsPrivacy() async {
  await analytics.setConsent(
    adStorageConsentGranted: false,
    analyticsStorageConsentGranted: true,
    adPersonalizationSignalsConsentGranted: false,
    adUserDataConsentGranted: false,
    functionalityStorageConsentGranted: true,
    personalizationStorageConsentGranted: false,
    securityStorageConsentGranted: true,
  );
  await analytics.setAnalyticsCollectionEnabled(true);
  await analytics.setDefaultEventParameters(null);
  await analytics.setUserId(id: null);
  await appAnalytics.configureAnonymousDeviceProperties();
}
