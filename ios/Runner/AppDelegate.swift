import Flutter
import UIKit
import SwiftUI
import Translation
import workmanager_apple
import BackgroundTasks
import flutter_local_notifications
import shared_preferences_foundation
import flutter_secure_storage_darwin
import package_info_plus
import app_badge_plus

private let adaptiveBackgroundTaskIdentifier = "com.blazesmoker.FANotifier.refresh"
private let adaptiveBackgroundIntervalKey = "flutter.backgroundFetchIntervalMinutes"
private let adaptiveBackgroundEmptyStreakKey = "flutter.backgroundFetchNoNotificationStreak"
private var pendingColdBackgroundLaunch = false
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
    private static var executionLeaseToken: String?
    private static var executionLeaseIssuedAt: Date?
    private static let executionLeaseMaxAge: TimeInterval = 2 * 60

    private var channel: FlutterMethodChannel?
    private var deadline: TimeInterval?
    private var cancellationTimer: Timer?
    private var launchContext = "foreground_engine"

    static func register(with registrar: FlutterPluginRegistrar) {
        register(with: registrar, startedAt: nil, launchContext: "foreground_engine")
    }

    static func register(
        with registrar: FlutterPluginRegistrar,
        startedAt: TimeInterval?,
        launchContext: String
    ) {
        let channel = FlutterMethodChannel(
            name: "app.background_fetch",
            binaryMessenger: registrar.messenger()
        )
        let instance = AdaptiveBackgroundFetchPlugin()
        instance.channel = channel
        instance.launchContext = launchContext
        if let startedAt = startedAt {
            instance.deadline = startedAt + 25
            let remaining = max(0, startedAt + 25 - ProcessInfo.processInfo.systemUptime)
            instance.cancellationTimer = Timer.scheduledTimer(withTimeInterval: remaining, repeats: false) { [weak instance] _ in
                instance?.channel?.invokeMethod("cancelRun", arguments: nil)
            }
        }
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "executionContext":
            var context: [String: Any] = ["launch_context": launchContext]
            if let deadline = deadline {
                context["remaining_ms"] = Int(max(0, deadline - ProcessInfo.processInfo.systemUptime) * 1000)
            }
            result(context)
        case "acquireExecution":
            if let deadline = deadline, ProcessInfo.processInfo.systemUptime >= deadline {
                result(nil)
            } else {
                result(Self.acquireExecutionLease())
            }
        case "releaseExecution":
            guard let arguments = call.arguments as? [String: Any],
                  let token = arguments["token"] as? String
            else {
                result(false)
                return
            }
            cancellationTimer?.invalidate()
            cancellationTimer = nil
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

        let defaults = UserDefaults.standard
        let activeAt = defaults.double(forKey: "flutter.isAppActiveAtMs")
        let activeAge = Date().timeIntervalSince1970 * 1000 - activeAt
        if defaults.bool(forKey: "flutter.isAppActive"),
           activeAt > 0, activeAge >= 0, activeAge <= 120000 {
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
    let startedAt = ProcessInfo.processInfo.systemUptime
    let launchContext = pendingColdBackgroundLaunch
        ? "cold_background_launch" : "existing_process_background"
    pendingColdBackgroundLaunch = false
    if let registrar = registry.registrar(forPlugin: "SharedPreferencesPlugin") {
        SharedPreferencesPlugin.register(with: registrar)
    }
    if let registrar = registry.registrar(forPlugin: "FlutterSecureStorageDarwinPlugin") {
        FlutterSecureStorageDarwinPlugin.register(with: registrar)
    }
    if let registrar = registry.registrar(forPlugin: "FPPPackageInfoPlusPlugin") {
        FPPPackageInfoPlusPlugin.register(with: registrar)
    }
    if let registrar = registry.registrar(forPlugin: "FlutterLocalNotificationsPlugin") {
        FlutterLocalNotificationsPlugin.register(with: registrar)
    }
    if let registrar = registry.registrar(forPlugin: "AppBadgePlusPlugin") {
        AppBadgePlusPlugin.register(with: registrar)
    }
    if let registrar = registry.registrar(forPlugin: "WorkmanagerPlugin") {
        WorkmanagerPlugin.register(with: registrar)
    }
    if let registrar = registry.registrar(forPlugin: "AdaptiveBackgroundFetchPlugin") {
        AdaptiveBackgroundFetchPlugin.register(
            with: registrar, startedAt: startedAt, launchContext: launchContext
        )
    }
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
        if key == "isAppActive" {
            if value {
                UserDefaults.standard.set(
                    Int64(Date().timeIntervalSince1970 * 1000),
                    forKey: "flutter.isAppActiveAtMs"
                )
            } else {
                UserDefaults.standard.removeObject(forKey: "flutter.isAppActiveAtMs")
            }
        }
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

    private lazy var fetchTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        formatter.timeZone  = .current
        return formatter
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
            self.fLog("[\(tag)] Next approx system fetch: \(self.fetchTimeFormatter.string(from: when)) (~\(rel))")
        }
    }

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {

        fLog("Application launching...")

        pendingColdBackgroundLaunch = application.applicationState == .background
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
        pendingColdBackgroundLaunch = false
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
