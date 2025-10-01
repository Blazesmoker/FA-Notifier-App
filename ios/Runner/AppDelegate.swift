import Flutter
import UIKit
import workmanager_apple
import BackgroundTasks
import flutter_secure_storage

@main
@objc class AppDelegate: FlutterAppDelegate {
    
    private let backgroundTaskIdentifier = "dev.flutter.backgroundFetch.ios.task"

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        
      

        NSLog("[AppDelegate] Application launching...")

        // Register Flutter plugins
        GeneratedPluginRegistrant.register(with: self)

        // Set notification delegate for handling foreground notifications
        UNUserNotificationCenter.current().delegate = self

        // Request notification permissions
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .badge, .sound]) { granted, error in
            NSLog("[AppDelegate] Notification permission granted: \(granted)")
            if let error = error {
                NSLog("[AppDelegate] Permission error: \(error)")
            }

            // Register for remote notifications on main thread if granted
            if granted {
                DispatchQueue.main.async {
                    application.registerForRemoteNotifications()
                }
            }
        }

        // CRITICAL: Register Workmanager plugin callback for background isolate
        WorkmanagerPlugin.setPluginRegistrantCallback { registry in
            GeneratedPluginRegistrant.register(with: registry)
            NSLog("[AppDelegate] Background isolate plugins registered")
        }

        // Register the background task handler with iOS BGTaskScheduler
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: backgroundTaskIdentifier,
            using: nil
        ) { [weak self] task in
            NSLog("[AppDelegate] ===============================================")
            NSLog("[AppDelegate] BACKGROUND TASK TRIGGERED BY iOS")
            NSLog("[AppDelegate] Time: \(Date())")
            NSLog("[AppDelegate] ===============================================")
            self?.handleBackgroundFetch(task: task)
        }

        // Schedule the initial background fetch
        scheduleBackgroundFetch()

        // List all pending tasks for debugging
        getPendingBackgroundTasks()

        NSLog("[AppDelegate] Application initialization complete")
        NSLog("[AppDelegate] Background task identifier: \(backgroundTaskIdentifier)")

        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    // Handle application entering background
    override func applicationDidEnterBackground(_ application: UIApplication) {
        NSLog("[AppDelegate] App entering background")
        scheduleBackgroundFetch()
    }

    // Handle application becoming active
    override func applicationDidBecomeActive(_ application: UIApplication) {
        NSLog("[AppDelegate] App became active")
        getPendingBackgroundTasks()
    }

    // Handle the background task
    private func handleBackgroundFetch(task: BGTask) {
        NSLog("[AppDelegate] handleBackgroundFetch started")

        // Schedule next fetch immediately
        scheduleBackgroundFetch()

        // Track task state
        var isTaskCompleted = false
        let taskStartTime = Date()

        // Set expiration handler
        task.expirationHandler = { [weak task] in
            let duration = Date().timeIntervalSince(taskStartTime)
            NSLog("[AppDelegate] Task expiration handler called after \(duration)s")

            if !isTaskCompleted {
                isTaskCompleted = true
                task?.setTaskCompleted(success: false)
                NSLog("[AppDelegate] Task marked as failed due to expiration")
            }
        }

        // Process the task
        if let refreshTask = task as? BGAppRefreshTask {
            NSLog("[AppDelegate] Task is BGAppRefreshTask, passing to WorkmanagerPlugin")

            // Create a completion handler
            let completionHandler: (Bool) -> Void = { success in
                let duration = Date().timeIntervalSince(taskStartTime)
                NSLog("[AppDelegate] Dart callback completed: success=\(success), duration=\(duration)s")

                if !isTaskCompleted {
                    isTaskCompleted = true
                    task.setTaskCompleted(success: success)
                    NSLog("[AppDelegate] Task marked as \(success ? "successful" : "failed")")
                }
            }

            // Pass to Workmanager which will call the Dart callback
            WorkmanagerPlugin.handlePeriodicTask(
                identifier: backgroundTaskIdentifier,
                task: refreshTask,
                earliestBeginInSeconds: nil,
                
            )


            // Safety timeout (28 seconds - iOS gives 30 seconds max)
            DispatchQueue.global().asyncAfter(deadline: .now() + 28.0) { [weak task] in
                if !isTaskCompleted {
                    let duration = Date().timeIntervalSince(taskStartTime)
                    NSLog("[AppDelegate] Safety timeout reached after \(duration)s")
                    isTaskCompleted = true
                    task?.setTaskCompleted(success: false)
                    NSLog("[AppDelegate] Task force-completed due to timeout")
                }
            }
        } else {
            NSLog("[AppDelegate] Task is not BGAppRefreshTask type")
            task.setTaskCompleted(success: false)
        }
    }

    // Schedule the next background fetch
    private func scheduleBackgroundFetch() {
        let request = BGAppRefreshTaskRequest(identifier: backgroundTaskIdentifier)

        // Set the earliest begin date to 15 minutes from now
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)

        do {
            try BGTaskScheduler.shared.submit(request)
            NSLog("[AppDelegate] ✓ Background fetch scheduled for \(request.earliestBeginDate?.description ?? "unknown")")
        } catch {
            // Check specific error cases
            let errorString = error.localizedDescription
            if errorString.contains("already scheduled") {
                NSLog("[AppDelegate] ℹ️ Background task already scheduled (this is normal)")
            } else if errorString.contains("too many") {
                NSLog("[AppDelegate] ⚠️ Too many tasks scheduled, will retry later")
            } else {
                NSLog("[AppDelegate] ❌ Failed to schedule: \(errorString)")
            }
        }
    }

    // Cancel all pending background tasks
    private func cancelAllBackgroundTasks() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: backgroundTaskIdentifier)
        NSLog("[AppDelegate] All background tasks cancelled")
    }

    // Get pending background tasks (for debugging)
    private func getPendingBackgroundTasks() {
        BGTaskScheduler.shared.getPendingTaskRequests { requests in
            NSLog("[AppDelegate] ===============================================")
            NSLog("[AppDelegate] PENDING BACKGROUND TASKS: \(requests.count)")
            for request in requests {
                NSLog("[AppDelegate] - ID: \(request.identifier)")
                NSLog("[AppDelegate]   Earliest: \(request.earliestBeginDate?.description ?? "immediately")")
            }
            if requests.isEmpty {
                NSLog("[AppDelegate] No pending background tasks")
            }
            NSLog("[AppDelegate] ===============================================")
        }
    }

    // MARK: - Notification Handling

    // Handle notifications when app is in foreground
    override func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        NSLog("[AppDelegate] Foreground notification: \(notification.request.content.title)")

        // Show notification even when app is in foreground
        if #available(iOS 14.0, *) {
            completionHandler([.banner, .sound, .badge, .list])
        } else {
            completionHandler([.alert, .sound, .badge])
        }
    }

    // Handle notification tap
    override func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        NSLog("[AppDelegate] Notification tapped: \(response.notification.request.content.title)")
        completionHandler()
    }

    // MARK: - Debug/Test Methods

    #if DEBUG
    // Method to test background fetch from Flutter (debug only)
    @objc func testBackgroundFetch() {
        NSLog("[AppDelegate] TEST: Manual background fetch trigger requested")

        // Cancel existing tasks
        cancelAllBackgroundTasks()

        // Schedule with very short interval for testing (60 seconds)
        let request = BGAppRefreshTaskRequest(identifier: backgroundTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60)

        do {
            try BGTaskScheduler.shared.submit(request)
            NSLog("[AppDelegate] TEST: Background fetch scheduled for 60 seconds from now")
            getPendingBackgroundTasks()
        } catch {
            NSLog("[AppDelegate] TEST: Failed to schedule: \(error)")
        }
    }

    // Simulate background fetch immediately (debug only)
    @objc func simulateBackgroundFetchNow() {
        NSLog("[AppDelegate] TEST: Simulating background fetch NOW")

        // This simulates iOS triggering a background fetch
        // Note: This may not work in all iOS versions
        BGTaskScheduler.shared.getPendingTaskRequests { requests in
            if let request = requests.first(where: { $0.identifier == self.backgroundTaskIdentifier }) {
                NSLog("[AppDelegate] TEST: Found pending task, attempting to trigger")
                // In debug builds, you can use private API to trigger
                // But it's better to use Xcode's Debug menu
            } else {
                NSLog("[AppDelegate] TEST: No pending task found to trigger")
            }
        }
    }
    #endif

    // MARK: - Application State Logging

    override func applicationWillResignActive(_ application: UIApplication) {
        NSLog("[AppDelegate] App will resign active")
    }

    override func applicationWillEnterForeground(_ application: UIApplication) {
        NSLog("[AppDelegate] App will enter foreground")
    }

    override func applicationWillTerminate(_ application: UIApplication) {
        NSLog("[AppDelegate] App will terminate")
    }
}
