import Flutter
import UIKit
import SwiftUI
import Translation
import workmanager_apple
import BackgroundTasks
import flutter_local_notifications

private let adaptiveBackgroundTaskIdentifier = "com.blazesmoker.FANotifier.refresh"
private let adaptiveBackgroundIntervalKey = "flutter.backgroundFetchIntervalMinutes"
private let adaptiveBackgroundEmptyStreakKey = "flutter.backgroundFetchNoNotificationStreak"
private let adaptiveBackgroundAsapSeconds: TimeInterval = 1

private func normalizedBackgroundFetchMinutes(_ minutes: Int) -> Int {
    minutes >= 30 ? 30 : 15
}

private func backgroundFetchLog(_ msg: String) {
    let line = "[AppDelegate] \(msg)"
    NSLog("%@", line)
    debugPrint("flutter: \(line)")
}

private func isAlreadyScheduledBackgroundFetchError(_ error: Error) -> Bool {
    let nsError = error as NSError
    let text = "\(nsError.domain) \(nsError.code) \(nsError.localizedDescription)".lowercased()
    return text.contains("already") &&
        (text.contains("scheduled") || text.contains("submitted"))
}

private func storedBackgroundFetchMinutes() -> Int {
    normalizedBackgroundFetchMinutes(UserDefaults.standard.integer(forKey: adaptiveBackgroundIntervalKey))
}

@discardableResult
private func submitBackgroundFetch(
    minutes: Int,
    replacingPending: Bool,
    earliestBeginInSeconds: TimeInterval? = nil
) throws -> Date {
    let normalizedMinutes = normalizedBackgroundFetchMinutes(minutes)
    UserDefaults.standard.set(normalizedMinutes, forKey: adaptiveBackgroundIntervalKey)
    UserDefaults.standard.synchronize()
    if replacingPending {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: adaptiveBackgroundTaskIdentifier)
        backgroundFetchLog("Cancelled pending BGTask for replacement")
    }
    let request = BGAppRefreshTaskRequest(identifier: adaptiveBackgroundTaskIdentifier)
    let delaySeconds = earliestBeginInSeconds ?? TimeInterval(normalizedMinutes * 60)
    let earliestBeginDate = Date(timeIntervalSinceNow: max(1, delaySeconds))
    request.earliestBeginDate = earliestBeginDate
    do {
        try BGTaskScheduler.shared.submit(request)
        backgroundFetchLog("Submitted BGTask earliest at \(earliestBeginDate) (~\(Int(max(0, earliestBeginDate.timeIntervalSinceNow)))s)")
    } catch {
        if isAlreadyScheduledBackgroundFetchError(error) {
            backgroundFetchLog("BGTask already scheduled; keeping existing request")
            return earliestBeginDate
        }
        throw error
    }
    return earliestBeginDate
}

final class AdaptiveBackgroundFetchPlugin: NSObject, FlutterPlugin {
    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "app.background_fetch",
            binaryMessenger: registrar.messenger()
        )
        registrar.addMethodCallDelegate(AdaptiveBackgroundFetchPlugin(), channel: channel)
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard call.method == "reschedule",
              let arguments = call.arguments as? [String: Any],
              let minutesNumber = arguments["minutes"] as? NSNumber
        else {
            result(FlutterMethodNotImplemented)
            return
        }
        let previousMinutes = normalizedBackgroundFetchMinutes(
            (arguments["previousMinutes"] as? NSNumber)?.intValue ?? storedBackgroundFetchMinutes()
        )
        do {
            let scheduledAt = try submitBackgroundFetch(
                minutes: minutesNumber.intValue,
                replacingPending: true
            )
            backgroundFetchLog("Dart requested BGTask reschedule for ~\(scheduledAt)")
            result(true)
        } catch let replacementError {
            do {
                let restoredAt = try submitBackgroundFetch(
                    minutes: previousMinutes,
                    replacingPending: false
                )
#if DEBUG
                backgroundFetchLog("Restored previous \(previousMinutes)m BGTask after replacement failure: \(restoredAt)")
#endif
                _ = restoredAt
            } catch let restorationError {
                result(FlutterError(
                    code: "background_fetch_reschedule_failed",
                    message: replacementError.localizedDescription,
                    details: [
                        "previousMinutes": previousMinutes,
                        "restorationError": restorationError.localizedDescription
                    ] as [String: Any]
                ))
                return
            }
            result(FlutterError(
                code: "background_fetch_reschedule_restored",
                message: replacementError.localizedDescription,
                details: ["restoredMinutes": previousMinutes]
            ))
        }
    }
}

func registerAdaptiveBackgroundFetchPlugin(registry: FlutterPluginRegistry) {
    guard let registrar = registry.registrar(forPlugin: "AdaptiveBackgroundFetchPlugin") else {
        NSLog("[AppDelegate] AdaptiveBackgroundFetchPlugin registrar unavailable")
        return
    }
    AdaptiveBackgroundFetchPlugin.register(with: registrar)
}

func registerPluginsForBackgroundIsolate(registry: FlutterPluginRegistry) {
    GeneratedPluginRegistrant.register(with: registry)
    registerAdaptiveBackgroundFetchPlugin(registry: registry)
    NSLog("[AppDelegate] Background isolate plugins registered")
}

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {

    private let backgroundTaskIdentifier = adaptiveBackgroundTaskIdentifier

    private func fLog(_ msg: String) {
        let line = "[AppDelegate] \(msg)"
        NSLog("%@", line)
        debugPrint("flutter: \(line)")
    }

    private func setFlutterSharedBool(_ value: Bool, forKey key: String) {
        UserDefaults.standard.set(value, forKey: "flutter.\(key)")
        UserDefaults.standard.synchronize()
    }

    private var translationChannel: FlutterMethodChannel?
    private var translationHostWindow: UIWindow?
    private weak var translationPreviousKeyWindow: UIWindow?

    private func configurePluginRegistrantCallbacks() {
        FlutterLocalNotificationsPlugin.setPluginRegistrantCallback { registry in
            GeneratedPluginRegistrant.register(with: registry)
        }
    }

    private func setupTranslationChannelIfNeeded(
        binaryMessenger: FlutterBinaryMessenger
    ) {
        guard translationChannel == nil else { return }

        let channel = FlutterMethodChannel(
            name: "app.translation",
            binaryMessenger: binaryMessenger
        )
        translationChannel = channel
        self.fLog("MethodChannel 'app.translation' initialized")

        channel.setMethodCallHandler { [weak self] call, result in
            guard let self = self else {
                result(FlutterError(code: "translation_unavailable", message: "AppDelegate deallocated", details: nil))
                return
            }

            switch call.method {
            case "translation.showNativeSheet":
                self.handleTranslationSheetCall(call, result: result)
            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }

    private func handleTranslationSheetCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
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
            var didComplete = false
            let completeOnce = { (requiresScrollRecovery: Bool) in
                guard !didComplete else { return }
                didComplete = true
                result([
                    "shown": true,
                    "requiresScrollRecovery": requiresScrollRecovery
                ])
            }
            let didPresent = self.presentNativeTranslationSheetIfAvailable(text: text) { requiresScrollRecovery in
                completeOnce(requiresScrollRecovery)
            }
            if !didPresent {
                result(false)
            }
        }
    }

    @MainActor
    private func presentNativeTranslationSheetIfAvailable(text: String, onDismiss: @escaping (Bool) -> Void) -> Bool {
        guard #available(iOS 17.4, *) else {
            return false
        }

        guard let windowScene = activeWindowScene() else {
            fLog("Translation sheet unavailable: active UIWindowScene not found")
            return false
        }

        guard translationHostWindow == nil else {
            fLog("Translation sheet unavailable: translation host already active")
            return false
        }

        let bridge = NativeTranslationSheetBridge(text: text) { [weak self] in
            guard let self = self else {
                onDismiss(true)
                return
            }
            self.removeTranslationHostIfNeeded(onDismiss: onDismiss)
        }

        let hostingController = UIHostingController(
            rootView: NativeTranslationSheetView(bridge: bridge)
        )
        hostingController.view.backgroundColor = .clear
        hostingController.view.isOpaque = false
        hostingController.view.clipsToBounds = false

        let hostWindow = UIWindow(windowScene: windowScene)
        hostWindow.rootViewController = hostingController
        hostWindow.backgroundColor = .clear
        hostWindow.isOpaque = false
        hostWindow.windowLevel = .alert + 1

        translationPreviousKeyWindow = windowScene.windows.first(where: { $0.isKeyWindow })
        translationHostWindow = hostWindow
        hostWindow.makeKeyAndVisible()
        fLog("Presented native translation host in isolated window")
        return true
    }

    @MainActor
    private func removeTranslationHostIfNeeded(onDismiss: @escaping (Bool) -> Void) {
        guard let hostWindow = translationHostWindow else {
            onDismiss(false)
            return
        }

        hostWindow.isHidden = true
        hostWindow.rootViewController = nil
        translationHostWindow = nil
        translationPreviousKeyWindow?.makeKey()
        translationPreviousKeyWindow = nil
        fLog("Dismissed native translation host")
        onDismiss(false)
    }

    @MainActor
    private func activeWindowScene() -> UIWindowScene? {
        if let scene = window?.windowScene {
            return scene
        }
        let windowScenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return windowScenes.first(where: { $0.activationState == .foregroundActive })
            ?? windowScenes.first(where: { $0.activationState == .foregroundInactive })
            ?? windowScenes.first
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

        if application.applicationState == .background {
            fLog("Background launch detected - skipping FlutterEngine.run for UI entrypoint")
        }
        UNUserNotificationCenter.current().delegate = self as UNUserNotificationCenterDelegate
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

        scheduleBackgroundFetch(
            asSoonAsPossible: false,
            source: "didFinishLaunching"
        )
        getPendingBackgroundTasks()
        logApproxNextFetch("didFinishLaunching")

        self.fLog("Application initialization complete")
        self.fLog("Background task identifier: \(backgroundTaskIdentifier)")

        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    func didInitializeImplicitFlutterEngine(
        _ engineBridge: FlutterImplicitEngineBridge
    ) {
        configurePluginRegistrantCallbacks()
        GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
        registerAdaptiveBackgroundFetchPlugin(registry: engineBridge.pluginRegistry)
        setupTranslationChannelIfNeeded(
            binaryMessenger: engineBridge.applicationRegistrar.messenger()
        )
    }

    func handleDidEnterBackground(source: String) {
        fLog("App entering background (\(source))")
        setFlutterSharedBool(false, forKey: "isAppActive")
        scheduleBackgroundFetch(asSoonAsPossible: false, source: "didEnterBackground:\(source)")
        logApproxNextFetch("didEnterBackground:\(source)")
    }

    func handleDidBecomeActive(source: String) {
        fLog("App became active (\(source))")
        setFlutterSharedBool(true, forKey: "isAppActive")
        UserDefaults.standard.set(0, forKey: adaptiveBackgroundEmptyStreakKey)
        do {
            let scheduledAt = try submitBackgroundFetch(
                minutes: 15,
                replacingPending: true
            )
            fLog("Background fetch reset to 15m after app became active: \(scheduledAt)")
        } catch {
            fLog("Failed to reset background fetch after app became active: \(error.localizedDescription)")
        }
        getPendingBackgroundTasks()
        logApproxNextFetch("didBecomeActive:\(source)")
    }

    private func handleBackgroundFetch(task: BGTask) {
        fLog("handleBackgroundFetch started")
        if let refreshTask = task as? BGAppRefreshTask {
            self.fLog("Task is BGAppRefreshTask, passing to WorkmanagerPlugin")
            let minutes = storedBackgroundFetchMinutes()
            self.fLog("Workmanager will request next BGTask at ~\(minutes)m")
            WorkmanagerPlugin.handlePeriodicTask(
                identifier: backgroundTaskIdentifier,
                task: refreshTask,
                earliestBeginInSeconds: Double(minutes * 60)
            )
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.logApproxNextFetch("after Workmanager handlePeriodicTask")
            }
        } else {
            fLog("Task is not BGAppRefreshTask type")
            task.setTaskCompleted(success: false)
        }
    }

    private func scheduleBackgroundFetch(
        asSoonAsPossible: Bool = false,
        source: String
    ) {
        let minutes = storedBackgroundFetchMinutes()
        do {
            let scheduledAt = try submitBackgroundFetch(
                minutes: minutes,
                replacingPending: false,
                earliestBeginInSeconds: asSoonAsPossible ? adaptiveBackgroundAsapSeconds : nil
            )
            let mode = asSoonAsPossible ? "ASAP" : "\(minutes)m"
            fLog("Background fetch scheduled from \(source) with \(mode) earliest request: \(scheduledAt)")
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
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else {
                    completionHandler()
                    return
                }
                self.userNotificationCenter(
                    center,
                    didReceive: response,
                    withCompletionHandler: completionHandler
                )
            }
            return
        }

        let content = response.notification.request.content
        fLog("Notification tapped: \(content.title) (action=\(response.actionIdentifier))")
        super.userNotificationCenter(
            center,
            didReceive: response,
            withCompletionHandler: completionHandler
        )
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
    private var didDismiss = false

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
        guard !nextValue, !didDismiss else { return }
        didDismiss = true
        onDismiss()
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
