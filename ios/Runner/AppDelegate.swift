import Flutter
import UIKit
import workmanager_apple
import BackgroundTasks
import flutter_secure_storage

// MARK: - Free function for Workmanager plugin registrant (no captures allowed)
func registerPluginsForBackgroundIsolate(registry: FlutterPluginRegistry) {
    GeneratedPluginRegistrant.register(with: registry)
    NSLog("[AppDelegate] Background isolate plugins registered")
}

@main
@objc class AppDelegate: FlutterAppDelegate {

    // MARK: - IDs
    private let backgroundTaskIdentifier = "com.blazesmoker.FANotifier.refresh"

    // MARK: - Logging helper (mirrors to NSLog + flutter print so "flutter" filter works)
    private func fLog(_ msg: String) {
        let line = "[AppDelegate] \(msg)"
        NSLog("%@", line)
        print("flutter: \(line)")
    }

    // MARK: - MethodChannel to forward notification taps to Dart
    private var notifChannel: FlutterMethodChannel?
    private var pendingNotificationPayload: [String: Any]? // hold taps until Dart is ready

    private func setupNotificationChannelIfNeeded() {
        guard notifChannel == nil,
              let controller = window?.rootViewController as? FlutterViewController
        else { return }

        let channel = FlutterMethodChannel(
            name: "app.notifications",
            binaryMessenger: controller.binaryMessenger
        )
        self.notifChannel = channel

        channel.setMethodCallHandler { [weak self] call, result in
            guard let self = self else { return }
            if call.method == "notifications.ready" {
                self.fLog("Dart confirmed notifications.ready")
                if let pending = self.pendingNotificationPayload {
                    self.fLog("Sending pending tapped notification to Dart")
                    channel.invokeMethod("notificationTapped", arguments: pending)
                    self.pendingNotificationPayload = nil
                }
                result(true)
            } else {
                result(FlutterMethodNotImplemented)
            }
        }

        self.fLog("MethodChannel 'app.notifications' initialized")
        if let pending = pendingNotificationPayload {
            self.fLog("Flushing previously pending tapped notification to Dart")
            channel.invokeMethod("notificationTapped", arguments: pending)
            pendingNotificationPayload = nil
        }
    }

    // MARK: - Approx next fetch logging
    private lazy var timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .medium
        f.timeZone  = .current
        return f
    }()

    private func logApproxNextFetch(_ tag: String) {
        BGTaskScheduler.shared.getPendingTaskRequests { [weak self] requests in
            guard let self = self else { return }
            guard let req = requests.first(where: { $0.identifier == self.backgroundTaskIdentifier }) else {
                self.fLog("[\(tag)] No pending request for \(self.backgroundTaskIdentifier)")
                return
            }
            let when = req.earliestBeginDate ?? Date()
            let secs = max(0, Int(when.timeIntervalSinceNow))
            let relFmt = DateComponentsFormatter()
            relFmt.allowedUnits = [.hour, .minute, .second]
            relFmt.unitsStyle = .short
            let rel = relFmt.string(from: TimeInterval(secs)) ?? "now"
            self.fLog("[\(tag)] Next approx system fetch: \(self.timeFmt.string(from: when)) (~\(rel))")
        }
    }

    // MARK: - App lifecycle
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {

        fLog("Application launching...")
        GeneratedPluginRegistrant.register(with: self)

        // Channel ASAP so we can forward any cold-start tap
        setupNotificationChannelIfNeeded()

        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            self.fLog("Notification permission granted: \(granted)")
            if let error = error { self.fLog("Permission error: \(error)") }
            if granted { DispatchQueue.main.async { application.registerForRemoteNotifications() } }
        }

        // IMPORTANT: pass the free function (no captures) here
        WorkmanagerPlugin.setPluginRegistrantCallback(registerPluginsForBackgroundIsolate)

        if #available(iOS 13.0, *) {
            BGTaskScheduler.shared.getPendingTaskRequests { reqs in
                for r in reqs where r.identifier.contains("dev.flutter.backgroundFetch.ios.task") {
                    self.fLog("Cancelling legacy request: \(r.identifier)")
                    BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: r.identifier)
                }
            }
        }

        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: backgroundTaskIdentifier,
            using: nil
        ) { [weak self] task in
            guard let self = self else { return }
            self.fLog("===============================================")
            self.fLog("BACKGROUND TASK TRIGGERED BY iOS (\(task.identifier))")
            self.fLog("Time: \(Date())")
            self.fLog("===============================================")
            self.handleBackgroundFetch(task: task)
        }

        scheduleBackgroundFetch()
        getPendingBackgroundTasks()
        logApproxNextFetch("didFinishLaunching")

        self.fLog("Application initialization complete")
        self.fLog("Background task identifier: \(backgroundTaskIdentifier)")

        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    override func applicationDidEnterBackground(_ application: UIApplication) {
        fLog("App entering background")
        scheduleBackgroundFetch()
        logApproxNextFetch("didEnterBackground")
    }

    override func applicationDidBecomeActive(_ application: UIApplication) {
        fLog("App became active")
        setupNotificationChannelIfNeeded()
        getPendingBackgroundTasks()
        logApproxNextFetch("didBecomeActive")
    }

    // MARK: - Background task handling
    private func handleBackgroundFetch(task: BGTask) {
        fLog("handleBackgroundFetch started")

        scheduleBackgroundFetch()
        logApproxNextFetch("after handle")

        var isTaskCompleted = false
        let taskStartTime = Date()

        task.expirationHandler = { [weak task] in
            let duration = Date().timeIntervalSince(taskStartTime)
            self.fLog("Task expiration handler called after \(duration)s")
            if !isTaskCompleted {
                isTaskCompleted = true
                task?.setTaskCompleted(success: false)
                self.fLog("Task marked as failed due to expiration")
            }
        }

        if let refreshTask = task as? BGAppRefreshTask {
            self.fLog("Task is BGAppRefreshTask, passing to WorkmanagerPlugin")
            WorkmanagerPlugin.handlePeriodicTask(
                identifier: backgroundTaskIdentifier,
                task: refreshTask,
                earliestBeginInSeconds: nil
            )

            DispatchQueue.global().asyncAfter(deadline: .now() + 28.0) { [weak task] in
                if !isTaskCompleted {
                    let duration = Date().timeIntervalSince(taskStartTime)
                    self.fLog("Safety timeout reached after \(duration)s")
                    isTaskCompleted = true
                    task?.setTaskCompleted(success: false)
                    self.fLog("Task force-completed due to timeout")
                }
            }
        } else {
            fLog("Task is not BGAppRefreshTask type")
            task.setTaskCompleted(success: false)
        }
    }

    // MARK: - Scheduling
    private func scheduleBackgroundFetch() {
        let request = BGAppRefreshTaskRequest(identifier: backgroundTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
            fLog("✓ Background fetch scheduled for \(request.earliestBeginDate?.description ?? "unknown")")
            logApproxNextFetch("after submit")
        } catch {
            let errorString = error.localizedDescription
            if errorString.contains("already scheduled") {
                fLog("ℹ️ Background task already scheduled (this is normal)")
                logApproxNextFetch("already scheduled")
            } else if errorString.contains("too many") {
                fLog("⚠️ Too many tasks scheduled, will retry later")
            } else {
                fLog("❌ Failed to schedule: \(errorString)")
            }
        }
    }

    private func cancelAllBackgroundTasks() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: backgroundTaskIdentifier)
        fLog("All background tasks cancelled")
    }

    private func getPendingBackgroundTasks() {
        BGTaskScheduler.shared.getPendingTaskRequests { requests in
            self.fLog("===============================================")
            self.fLog("PENDING BACKGROUND TASKS: \(requests.count)")
            for request in requests {
                self.fLog("- ID: \(request.identifier)")
                self.fLog("  Earliest: \(request.earliestBeginDate?.description ?? "immediately")")
            }
            if requests.isEmpty {
                self.fLog("No pending background tasks")
            }
            self.fLog("===============================================")
        }
        logApproxNextFetch("getPendingBackgroundTasks")
    }

    // MARK: - Notification Handling
    override func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        fLog("Foreground notification: \(notification.request.content.title)")
        // Show banner while foregrounded so user can tap it
        if #available(iOS 14.0, *) {
            completionHandler([.banner, .sound, .badge, .list])
        } else {
            completionHandler([.alert, .sound, .badge])
        }
    }

    override func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let content = response.notification.request.content
        fLog("Notification tapped: \(content.title) (action=\(response.actionIdentifier))")

        // Forward the tap to Dart — this works for foreground/background/cold start
        let payload = makePayload(from: response)
        if let channel = notifChannel {
            fLog("Forwarding tap to Dart via MethodChannel")
            channel.invokeMethod("notificationTapped", arguments: payload)
        } else {
            fLog("MethodChannel not ready yet – caching tapped notification")
            pendingNotificationPayload = payload
        }

        completionHandler()
    }

    private func makePayload(from response: UNNotificationResponse) -> [String: Any] {
        let content = response.notification.request.content
        let info = stringifyUserInfo(content.userInfo)
        var payload: [String: Any] = [
            "id": response.notification.request.identifier,
            "title": content.title,
            "body": content.body,
            "actionIdentifier": response.actionIdentifier,
            "categoryIdentifier": content.categoryIdentifier,
            "threadIdentifier": content.threadIdentifier,
            "timestamp": Int(Date().timeIntervalSince1970),
            "userInfo": info
        ]
        if let dartPayload = content.userInfo["payload"] as? String {
            payload["payload"] = dartPayload
        }
        return payload
    }

    private func stringifyUserInfo(_ userInfo: [AnyHashable: Any]) -> [String: Any] {
        var out: [String: Any] = [:]
        for (k, v) in userInfo {
            let key = String(describing: k)
            switch v {
            case let s as String:        out[key] = s
            case let n as NSNumber:      out[key] = n
            case let b as Bool:          out[key] = b
            case let d as Double:        out[key] = d
            case let i as Int:           out[key] = i
            case let arr as [Any]:
                out[key] = arr.map { String(describing: $0) }
            case let dict as [AnyHashable: Any]:
                out[key] = stringifyUserInfo(dict)
            default:
                out[key] = String(describing: v)
            }
        }
        return out
    }

    // MARK: - Debug/Test
    #if DEBUG
    @objc func testBackgroundFetch() {
        fLog("TEST: Manual background fetch trigger requested")
        cancelAllBackgroundTasks()
        let request = BGAppRefreshTaskRequest(identifier: backgroundTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60)
        do {
            try BGTaskScheduler.shared.submit(request)
            fLog("TEST: Background fetch scheduled for 60 seconds from now")
            getPendingBackgroundTasks()
            logApproxNextFetch("testBackgroundFetch")
        } catch {
            fLog("TEST: Failed to schedule: \(error)")
        }
    }

    @objc func simulateBackgroundFetchNow() {
        fLog("TEST: Simulating background fetch NOW")
        BGTaskScheduler.shared.getPendingTaskRequests { requests in
            if let _ = requests.first(where: { $0.identifier == self.backgroundTaskIdentifier }) {
                self.fLog("TEST: Found pending task, attempting to trigger")
            } else {
                self.fLog("TEST: No pending task found to trigger")
            }
        }
        logApproxNextFetch("simulateBackgroundFetchNow")
    }
    #endif

    // MARK: - App state logs
    override func applicationWillResignActive(_ application: UIApplication) {
        fLog("App will resign active")
    }
    override func applicationWillEnterForeground(_ application: UIApplication) {
        fLog("App will enter foreground")
    }
    override func applicationWillTerminate(_ application: UIApplication) {
        fLog("App will terminate")
    }
}
