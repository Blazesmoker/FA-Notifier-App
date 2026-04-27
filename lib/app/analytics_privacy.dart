import 'package:firebase_analytics/firebase_analytics.dart';

final FirebaseAnalytics analytics = FirebaseAnalytics.instance;

Future<void> setupAnalyticsPrivacy() async {
  await analytics.setAnalyticsCollectionEnabled(true);

  await analytics.setDefaultEventParameters({
    'allow_ad_personalization_signals': 'false',
  });
}
