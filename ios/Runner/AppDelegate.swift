import Flutter
import UIKit
import UserNotifications
import workmanager
import flutter_app_badge_control


@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {

    // Register the plugin registrant callback for the background isolate.
    WorkmanagerPlugin.setPluginRegistrantCallback { (registry) in
      GeneratedPluginRegistrant.register(with: registry)
    }


    // Register plugins for the main isolate.
    GeneratedPluginRegistrant.register(with: self)

    // Set the notification delegate to self.
    UNUserNotificationCenter.current().delegate = self

    // Ask iOS to perform background fetch as frequently as possible.
    application.setMinimumBackgroundFetchInterval(UIApplication.backgroundFetchIntervalMinimum)

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // Foreground notification presentation method remains unchanged.
  override func userNotificationCenter(_ center: UNUserNotificationCenter,
                              willPresent notification: UNNotification,
                              withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
    if #available(iOS 14.0, *) {
      completionHandler([.banner, .sound, .badge])
    } else {
      completionHandler([.alert, .sound, .badge])
    }
  }
}
