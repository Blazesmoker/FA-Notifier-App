import Flutter
import UIKit
import SwiftUI
import Translation
import workmanager_apple
import BackgroundTasks
import flutter_secure_storage

func registerPluginsForBackgroundIsolate(registry: FlutterPluginRegistry) {
    GeneratedPluginRegistrant.register(with: registry)
    NSLog("[AppDelegate] Background isolate plugins registered")
}

@main
@objc class AppDelegate: FlutterAppDelegate {

    var flutterEngine: FlutterEngine?

    private let backgroundTaskIdentifier = "com.blazesmoker.FANotifier.refresh"

    private func fLog(_ msg: String) {
        let line = "[AppDelegate] \(msg)"
        NSLog("%@", line)
        debugPrint("flutter: \(line)")
    }

    private var notifChannel: FlutterMethodChannel?
    private var pendingNotificationPayload: [String: Any]?
    private var translationChannel: FlutterMethodChannel?
    private var translationHostController: UIViewController?

    private func findFlutterViewController() -> FlutterViewController? {
        if let vc = window?.rootViewController as? FlutterViewController {
            return vc
        }
        if #available(iOS 13.0, *) {
            for scene in UIApplication.shared.connectedScenes {
                guard let windowScene = scene as? UIWindowScene else { continue }
                for w in windowScene.windows {
                    if let fc = w.rootViewController as? FlutterViewController {
                        return fc
                    }
                    if let nav = w.rootViewController as? UINavigationController,
                       let fc = nav.viewControllers.first(where: { $0 is FlutterViewController }) as? FlutterViewController {
                        return fc
                    }
                }
            }
        }
        return nil
    }

    func setupNotificationChannelIfNeeded() {
        guard notifChannel == nil,
              let controller = findFlutterViewController()
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

    func setupTranslationChannelIfNeeded() {
        guard translationChannel == nil,
              let controller = findFlutterViewController()
        else { return }

        let channel = FlutterMethodChannel(
            name: "app.translation",
            binaryMessenger: controller.binaryMessenger
        )
        translationChannel = channel
        self.fLog("MethodChannel 'app.translation' initialized")

        channel.setMethodCallHandler { [weak self] call, result in
            guard let self = self else {
                result(FlutterError(code: "translation_unavailable", message: "AppDelegate deallocated", details: nil))
                return
            }

            guard call.method == "translation.showNativeSheet" else {
                result(FlutterMethodNotImplemented)
                return
            }

            let rawText: String?
            if let args = call.arguments as? [String: Any] {
                rawText = args["text"] as? String
            } else {
                rawText = call.arguments as? String
            }

            let text = rawText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !text.isEmpty else {
                result(false)
                return
            }

            DispatchQueue.main.async {
                result(self.presentNativeTranslationSheetIfAvailable(text: text))
            }
        }
    }

    @MainActor
    private func presentNativeTranslationSheetIfAvailable(text: String) -> Bool {
        guard #available(iOS 17.4, *) else {
            return false
        }

        guard let anchorController = findFlutterViewController() else {
            fLog("Translation sheet unavailable: FlutterViewController not found")
            return false
        }

        removeTranslationHostIfNeeded()

        let bridge = NativeTranslationSheetBridge(text: text) { [weak self] in
            self?.removeTranslationHostIfNeeded()
        }

        let hostingController = UIHostingController(
            rootView: NativeTranslationSheetView(bridge: bridge)
        )
        hostingController.view.backgroundColor = .clear
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false

        anchorController.addChild(hostingController)
        anchorController.view.addSubview(hostingController.view)
        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: anchorController.view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: anchorController.view.trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: anchorController.view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: anchorController.view.bottomAnchor)
        ])
        hostingController.didMove(toParent: anchorController)
        translationHostController = hostingController
        fLog("Presenting native translation sheet")
        return true
    }

    @MainActor
    private func removeTranslationHostIfNeeded() {
        guard let host = translationHostController else { return }

        if host.presentingViewController != nil {
            host.dismiss(animated: false)
        }

        if host.parent != nil {
            host.willMove(toParent: nil)
            host.view.removeFromSuperview()
            host.removeFromParent()
        }

        translationHostController = nil
    }

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

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {

        fLog("Application launching...")

        let isBackgroundLaunch = application.applicationState == .background
        if isBackgroundLaunch {
            fLog("Background launch detected - skipping FlutterEngine.run for UI entrypoint")
        } else {
            let engine = FlutterEngine(name: "shared_engine")
            engine.run()
            self.flutterEngine = engine
            GeneratedPluginRegistrant.register(with: engine)
        }
        GeneratedPluginRegistrant.register(with: self)
        setupNotificationChannelIfNeeded()
        setupTranslationChannelIfNeeded()
        UNUserNotificationCenter.current().delegate = self
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
        handleDidEnterBackground(source: "appDelegate")
    }

    override func applicationDidBecomeActive(_ application: UIApplication) {
        handleDidBecomeActive(source: "appDelegate")
    }

    func handleDidEnterBackground(source: String) {
        fLog("App entering background (\(source))")
        scheduleBackgroundFetch()
        logApproxNextFetch("didEnterBackground:\(source)")
    }

    func handleDidBecomeActive(source: String) {
        fLog("App became active (\(source))")
        setupNotificationChannelIfNeeded()
        setupTranslationChannelIfNeeded()
        getPendingBackgroundTasks()
        logApproxNextFetch("didBecomeActive:\(source)")
    }

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

    override func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        fLog("Foreground notification: \(notification.request.content.title)")
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

@available(iOS 17.4, *)
@MainActor
final class NativeTranslationSheetBridge: ObservableObject {
    @Published var isPresented = false

    let text: String
    private let onDismiss: () -> Void
    private var didTriggerPresentation = false

    init(text: String, onDismiss: @escaping () -> Void) {
        self.text = text
        self.onDismiss = onDismiss
    }

    func triggerPresentationIfNeeded() {
        guard !didTriggerPresentation else { return }
        didTriggerPresentation = true
        DispatchQueue.main.async {
            self.isPresented = true
        }
    }

    func handlePresentationChange(_ nextValue: Bool) {
        if !nextValue {
            onDismiss()
        }
    }
}

@available(iOS 17.4, *)
struct NativeTranslationSheetView: View {
    @ObservedObject var bridge: NativeTranslationSheetBridge

    var body: some View {
        Color.clear
            .ignoresSafeArea()
            .translationPresentation(
                isPresented: $bridge.isPresented,
                text: bridge.text
            )
            .onAppear {
                bridge.triggerPresentationIfNeeded()
            }
            .onChange(of: bridge.isPresented) { _, nextValue in
                bridge.handlePresentationChange(nextValue)
            }
    }
}
