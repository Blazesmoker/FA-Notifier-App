import Flutter
import UIKit
import UserNotifications
import flutter_app_badge_control
import workmanager_apple
import BackgroundTasks

@main
@objc class AppDelegate: FlutterAppDelegate {

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {

        // Register plugins
        GeneratedPluginRegistrant.register(with: self)

        // Set notification delegate
        UNUserNotificationCenter.current().delegate = self

        // Request notification permissions
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .badge, .sound]) { granted, error in
            NSLog("[AppDelegate] Notification permission granted: \(granted)")
            if let error = error {
                NSLog("[AppDelegate] Permission error: \(error)")
            }
        }

        // Register Flutter plugins in background isolate
        WorkmanagerPlugin.setPluginRegistrantCallback { registry in
            GeneratedPluginRegistrant.register(with: registry)
            NSLog("[AppDelegate] Flutter plugins registered in background")
        }

    

        NSLog("[AppDelegate] Workmanager setup complete")

        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    override func applicationDidEnterBackground(_ application: UIApplication) {
        NSLog("[AppDelegate] App entered background")
        super.applicationDidEnterBackground(application)
    }

    #if DEBUG
    override func applicationDidBecomeActive(_ application: UIApplication) {
        super.applicationDidBecomeActive(application)

        NSLog("[DEBUG] App became active")

        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            NSLog("[DEBUG] Checking for scheduled tasks")


        }
    }
    #endif

    override func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        NSLog("[AppDelegate] Will present notification: \(notification.request.content.title)")
        if #available(iOS 14.0, *) {
            completionHandler([.banner, .sound, .badge])
        } else {
            completionHandler([.alert, .sound, .badge])
        }
    }
}
