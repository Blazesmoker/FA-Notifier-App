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
private let iOSBackgroundFetchIntervalMinutes = 15
private let iOSBackgroundFetchIntervalSeconds: TimeInterval = 15 * 60

private func backgroundFetchLog(_ msg: String) {
    let line = "[AppDelegate] \(msg)"
    NSLog("%@", line)
    debugPrint("flutter: \(line)")
}

@discardableResult
private func submitBackgroundFetch() throws -> Date {
    UserDefaults.standard.set(
        iOSBackgroundFetchIntervalMinutes,
        forKey: adaptiveBackgroundIntervalKey
    )
    UserDefaults.standard.synchronize()
    let request = BGAppRefreshTaskRequest(identifier: adaptiveBackgroundTaskIdentifier)
    let earliestBeginDate = Date(
        timeIntervalSinceNow: iOSBackgroundFetchIntervalSeconds
    )
    request.earliestBeginDate = earliestBeginDate
    try BGTaskScheduler.shared.submit(request)
    backgroundFetchLog(
        "Submitted BGTask earliest at \(earliestBeginDate) " +
        "(~\(Int(iOSBackgroundFetchIntervalSeconds))s)"
    )
    return earliestBeginDate
}

final class AdaptiveBackgroundFetchPlugin: NSObject, FlutterPlugin {
    private static let executionLeaseLock = NSLock()
    private static weak var activityStateOwner: AdaptiveBackgroundFetchPlugin?
    private static var activityStateToken: String?
    private static var executionLeaseToken: String?
    private static var executionLeaseIssuedAt: Date?
    private static let executionLeaseMaxAge: TimeInterval = 2 * 60

    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "app.background_fetch",
            binaryMessenger: registrar.messenger()
        )
        registrar.addMethodCallDelegate(AdaptiveBackgroundFetchPlugin(), channel: channel)
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "acquireActivityState":
            Self.executionLeaseLock.lock()
            if Self.activityStateOwner == nil {
                let token = UUID().uuidString
                Self.activityStateOwner = self
                Self.activityStateToken = token
                Self.executionLeaseLock.unlock()
                result(token)
            } else {
                Self.executionLeaseLock.unlock()
                result(nil)
            }
        case "releaseActivityState":
            Self.executionLeaseLock.lock()
            if Self.activityStateOwner === self,
               let token = call.arguments as? String,
               Self.activityStateToken == token {
                Self.activityStateOwner = nil
                Self.activityStateToken = nil
            }
            Self.executionLeaseLock.unlock()
            result(nil)
        case "acquireExecution":
            result(Self.acquireExecutionLease())
        case "releaseExecution":
            guard let arguments = call.arguments as? [String: Any],
                  let token = arguments["token"] as? String
            else {
                result(false)
                return
            }
            result(Self.releaseExecutionLease(token: token))
        case "reschedule":
            UserDefaults.standard.set(
                iOSBackgroundFetchIntervalMinutes,
                forKey: adaptiveBackgroundIntervalKey
            )
            UserDefaults.standard.set(0, forKey: adaptiveBackgroundEmptyStreakKey)
            UserDefaults.standard.synchronize()
            result(true)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private static func acquireExecutionLease() -> String? {
        executionLeaseLock.lock()
        defer { executionLeaseLock.unlock() }

        if UserDefaults.standard.bool(forKey: "flutter.isAppActive") {
            return nil
        }
        if executionLeaseToken != nil {
            let now = Date()
            if let issuedAt = executionLeaseIssuedAt,
               now.timeIntervalSince(issuedAt) < executionLeaseMaxAge {
                return nil
            }
            executionLeaseToken = nil
            executionLeaseIssuedAt = nil
        }

        let token = UUID().uuidString
        executionLeaseToken = token
        executionLeaseIssuedAt = Date()
        return token
    }

    private static func releaseExecutionLease(token: String) -> Bool {
        executionLeaseLock.lock()
        defer { executionLeaseLock.unlock() }

        guard executionLeaseToken == token else { return false }
        executionLeaseToken = nil
        executionLeaseIssuedAt = nil
        return true
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
    FARegisterBackgroundPlugins(registry)
    registerAdaptiveBackgroundFetchPlugin(registry: registry)
    NSLog("[AppDelegate] Background isolate plugins registered")
}

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {

    private let backgroundTaskIdentifier = adaptiveBackgroundTaskIdentifier
    private var notificationPluginsReady = false
    private var pendingNotificationResponses: [UNNotificationResponse] = []
    private var handledNotificationResponses: [String] = []

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
            setFlutterSharedBool(false, forKey: "isAppActive")
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

        WorkmanagerPlugin.registerPeriodicTask(
            withIdentifier: backgroundTaskIdentifier,
            earliestBeginInSeconds: NSNumber(
                value: iOSBackgroundFetchIntervalSeconds
            )
        )

        scheduleBackgroundFetch(source: "didFinishLaunching")
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
        notificationPluginsReady = true
        let responses = pendingNotificationResponses
        pendingNotificationResponses.removeAll()
        for response in responses {
            super.userNotificationCenter(
                UNUserNotificationCenter.current(),
                didReceive: response,
                withCompletionHandler: {}
            )
        }
        setupTranslationChannelIfNeeded(
            binaryMessenger: engineBridge.applicationRegistrar.messenger()
        )
    }

    func handleDidEnterBackground(source: String) {
        fLog("App entering background (\(source))")
        setFlutterSharedBool(false, forKey: "isAppActive")
        scheduleBackgroundFetch(source: "didEnterBackground:\(source)")
        logApproxNextFetch("didEnterBackground:\(source)")
    }

    func handleDidBecomeActive(source: String) {
        fLog("App became active (\(source))")
        setFlutterSharedBool(true, forKey: "isAppActive")
        UserDefaults.standard.set(0, forKey: adaptiveBackgroundEmptyStreakKey)
        UserDefaults.standard.set(
            iOSBackgroundFetchIntervalMinutes,
            forKey: adaptiveBackgroundIntervalKey
        )
        UserDefaults.standard.synchronize()
        scheduleBackgroundFetch(source: "didBecomeActive:\(source)")
        getPendingBackgroundTasks()
        logApproxNextFetch("didBecomeActive:\(source)")
    }

    private func scheduleBackgroundFetch(source: String) {
        BGTaskScheduler.shared.getPendingTaskRequests { [weak self] requests in
            guard let self = self else { return }
            if requests.contains(where: {
                $0.identifier == self.backgroundTaskIdentifier
            }) {
                self.fLog(
                    "Background fetch already pending from \(source); keeping it"
                )
                self.logApproxNextFetch("pending:\(source)")
                return
            }
            do {
                let scheduledAt = try submitBackgroundFetch()
                self.fLog(
                    "Background fetch scheduled from \(source) with 15m " +
                    "earliest request: \(scheduledAt)"
                )
                self.logApproxNextFetch("submitted:\(source)")
            } catch {
                self.fLog(
                    "Failed to schedule background fetch from \(source): " +
                    error.localizedDescription
                )
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

        let request = response.notification.request
        let responseKey = "\(request.identifier):\(response.notification.date.timeIntervalSince1970):\(response.actionIdentifier)"
        if handledNotificationResponses.contains(responseKey) {
            completionHandler()
            return
        }
        handledNotificationResponses.append(responseKey)
        if handledNotificationResponses.count > 16 {
            handledNotificationResponses.removeFirst()
        }
        if !notificationPluginsReady {
            pendingNotificationResponses.append(response)
            completionHandler()
            return
        }
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
        request.earliestBeginDate = Date(
            timeIntervalSinceNow: iOSBackgroundFetchIntervalSeconds
        )
        do {
            try BGTaskScheduler.shared.submit(request)
            fLog("TEST: Background fetch scheduled for 15 minutes from now")
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
