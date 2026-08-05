import Flutter
import UIKit
import SwiftUI
import Translation
import workmanager_apple
import BackgroundTasks
import flutter_local_notifications
import flutter_secure_storage_darwin
import package_info_plus
import shared_preferences_foundation

private let adaptiveBackgroundTaskIdentifier = "com.blazesmoker.FANotifier.refresh"
private let adaptiveBackgroundIntervalKey = "flutter.backgroundFetchIntervalMinutes"
private let adaptiveBackgroundEmptyStreakKey = "flutter.backgroundFetchNoNotificationStreak"
private let adaptiveBackgroundAsapSeconds: TimeInterval = 1
private let experimentalStableBackgroundFetchFlagKey =
    "FAExperimentalStableIOSBackgroundFetchEnabled"
private let stableFetchDiagnosticsFlagKey =
    "FAStableFetchDiagnosticsEnabled"
private let experimentalStableBackgroundFetchPreferenceKey =
    "flutter.experimentalStableIOSBackgroundFetchEnabled"
private let experimentalStableBackgroundFetchChannelName =
    "app.experimental_ios_stable_fetch"
private let experimentalStableBackgroundFetchEntrypoint =
    "experimentalIosStableFetchEntrypoint"
private let experimentalStableBackgroundFetchReadyTimeout: TimeInterval = 5
private let experimentalStableBackgroundQuiescenceSeconds: TimeInterval = 30
private let experimentalStableBackgroundWatchdogGraceSeconds: TimeInterval = 5 * 60
private let experimentalStableBackgroundWatchdogDeadlineKey =
    "experimentalStableIOSBackgroundWatchdogDeadline"
private let experimentalStableBackgroundNextDueAtMsKey =
    "flutter.experimentalStableIOSBackgroundNextDueAtMs"
private let experimentalStableBackgroundNextExecutionEligibleAtKey =
    "experimentalStableIOSBackgroundNextExecutionEligibleAt"
private let experimentalStableBackgroundLastTimerTickAtMsKey =
    "flutter.experimentalStableIOSBackgroundLastTimerTickAtMs"
private let experimentalStableBackgroundLastRunAtMsKey =
    "flutter.experimentalStableIOSBackgroundLastRunAtMs"
private let experimentalStableBackgroundLastWakeProducerKey =
    "flutter.experimentalStableIOSBackgroundLastWakeProducer"
private let experimentalStableBackgroundExecutionLeaseMaxRuntime: TimeInterval =
    30 * 60
private let stableFetchDiagnosticTraceMaxBytes: UInt64 = 512 * 1024
private let stableFetchDiagnosticTraceQueue = DispatchQueue(
    label: "com.blazesmoker.FANotifier.stableFetchDiagnostics"
)
private let stableFetchDiagnosticTraceURL: URL = {
    let cachesURL = FileManager.default.urls(
        for: .cachesDirectory,
        in: .userDomainMask
    ).first ?? FileManager.default.temporaryDirectory
    return cachesURL.appendingPathComponent("ios_stable_fetch.log")
}()

private func experimentalStableBackgroundFetchFlagEnabled() -> Bool {
    (Bundle.main.object(
        forInfoDictionaryKey: experimentalStableBackgroundFetchFlagKey
    ) as? NSNumber)?.boolValue ?? false
}

private func stableFetchDiagnosticsEnabled() -> Bool {
    #if DEBUG
    return (Bundle.main.object(
        forInfoDictionaryKey: stableFetchDiagnosticsFlagKey
    ) as? NSNumber)?.boolValue ?? false
    #else
    return false
    #endif
}
private func stableFetchDiagnosticDate(_ date: Date?) -> String {
    guard let date else { return "none" }
    return ISO8601DateFormatter().string(from: date)
}

private func persistStableFetchDiagnosticLine(_ line: String) {
    guard stableFetchDiagnosticsEnabled(),
          let data = (line + "\n").data(using: .utf8)
    else {
        return
    }
    stableFetchDiagnosticTraceQueue.async {
        let fileManager = FileManager.default
        let traceURL = stableFetchDiagnosticTraceURL
        let rotatedURL = traceURL.appendingPathExtension("1")
        let size = ((try? fileManager.attributesOfItem(
            atPath: traceURL.path
        )[.size]) as? NSNumber)?.uint64Value ?? 0
        if size + UInt64(data.count) > stableFetchDiagnosticTraceMaxBytes {
            try? fileManager.removeItem(at: rotatedURL)
            if fileManager.fileExists(atPath: traceURL.path) {
                try? fileManager.moveItem(at: traceURL, to: rotatedURL)
            }
        }
        if !fileManager.fileExists(atPath: traceURL.path) {
            _ = fileManager.createFile(
                atPath: traceURL.path,
                contents: nil
            )
        }
        guard let handle = try? FileHandle(forWritingTo: traceURL) else {
            return
        }
        handle.seekToEndOfFile()
        handle.write(data)
        handle.closeFile()
    }
}

private func stableFetchDiagnostic(
    _ event: String,
    fields: [String: Any] = [:]
) {
    guard stableFetchDiagnosticsEnabled() else { return }
    let now = Date()
    var payload = fields
    payload["event"] = event
    if payload["origin"] == nil {
        payload["origin"] = "native"
    }
    payload["wallUtc"] = ISO8601DateFormatter().string(from: now)
    payload["epochMs"] = Int64(now.timeIntervalSince1970 * 1000)
    payload["systemUptimeMs"] = Int64(
        ProcessInfo.processInfo.systemUptime * 1000
    )
    payload["pid"] = ProcessInfo.processInfo.processIdentifier
    guard JSONSerialization.isValidJSONObject(payload),
          let data = try? JSONSerialization.data(
            withJSONObject: payload,
            options: [.sortedKeys]
          ),
          let json = String(data: data, encoding: .utf8)
    else {
        let fallback = "[IOS_STABLE_FETCH] event=\(event) serialization=failed"
        NSLog("%@", fallback)
        persistStableFetchDiagnosticLine(fallback)
        return
    }
    let line = "[IOS_STABLE_FETCH] \(json)"
    NSLog("%@", line)
    persistStableFetchDiagnosticLine(line)
}

private func stableFetchDiagnosticSnapshot() -> [String: Any] {
    let defaults = UserDefaults.standard
    let nextDueAt = storedExperimentalBackgroundNextDueAt()
    let watchdogDeadline = storedExperimentalBackgroundWatchdogDeadline()
    let eligibleTimestamp = defaults.double(
        forKey: experimentalStableBackgroundNextExecutionEligibleAtKey
    )
    let lastTimerTick = defaults.double(
        forKey: experimentalStableBackgroundLastTimerTickAtMsKey
    )
    let lastRun = defaults.double(
        forKey: experimentalStableBackgroundLastRunAtMsKey
    )
    return [
        "nextDueAt": stableFetchDiagnosticDate(nextDueAt),
        "watchdogDeadline": stableFetchDiagnosticDate(watchdogDeadline),
        "leaseEligibleAt": eligibleTimestamp > 0
            ? stableFetchDiagnosticDate(
                Date(timeIntervalSince1970: eligibleTimestamp)
              )
            : "none",
        "lastTimerTickAtMs": Int64(lastTimerTick),
        "lastRunAtMs": Int64(lastRun),
        "lastWakeProducer": defaults.string(
            forKey: experimentalStableBackgroundLastWakeProducerKey
        ) ?? "none"
    ]
}

private func stableFetchDiagnosticPendingRequest(_ source: String) {
    guard stableFetchDiagnosticsEnabled() else { return }
    BGTaskScheduler.shared.getPendingTaskRequests { requests in
        let request = requests.first {
            $0.identifier == adaptiveBackgroundTaskIdentifier
        }
        stableFetchDiagnostic(
            "WATCHDOG_PENDING_SNAPSHOT",
            fields: [
                "source": source,
                "requestCount": requests.count,
                "earliestBeginDate": stableFetchDiagnosticDate(
                    request?.earliestBeginDate
                )
            ]
        )
    }
}

private func normalizedBackgroundFetchMinutes(_ minutes: Int) -> Int {
    minutes >= 30 ? 30 : 2
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

private func experimentalBackgroundWatchdogDelaySeconds(
    minutes: Int,
    nextDueAt: Date? = nil
) -> TimeInterval {
    let timerDueAt = nextDueAt ??
        storedExperimentalBackgroundNextDueAt() ??
        Date(
            timeIntervalSinceNow:
                TimeInterval(normalizedBackgroundFetchMinutes(minutes) * 60)
        )
    return max(
        1,
        timerDueAt.timeIntervalSinceNow +
            experimentalStableBackgroundWatchdogGraceSeconds
    )
}

private func storedExperimentalBackgroundNextDueAt() -> Date? {
    let milliseconds = UserDefaults.standard.double(
        forKey: experimentalStableBackgroundNextDueAtMsKey
    )
    guard milliseconds > 0 else { return nil }
    return Date(timeIntervalSince1970: milliseconds / 1000)
}

private func storedExperimentalBackgroundWatchdogDeadline() -> Date? {
    let timestamp = UserDefaults.standard.double(
        forKey: experimentalStableBackgroundWatchdogDeadlineKey
    )
    guard timestamp > 0 else { return nil }
    return Date(timeIntervalSince1970: timestamp)
}

private func clearExperimentalBackgroundWatchdogDeadline() {
    let previousDeadline = storedExperimentalBackgroundWatchdogDeadline()
    UserDefaults.standard.removeObject(
        forKey: experimentalStableBackgroundWatchdogDeadlineKey
    )
    UserDefaults.standard.synchronize()
    stableFetchDiagnostic(
        "WATCHDOG_DEADLINE_CLEARED",
        fields: [
            "previousDeadline": stableFetchDiagnosticDate(previousDeadline)
        ]
    )
}

private func workmanagerBackgroundCallbackIsAvailable() -> Bool {
    let defaults = UserDefaults(
        suiteName: "dev.fluttercommunity.workmanager.userDefaults"
    )
    guard let handle = defaults?.object(
        forKey: "dev.fluttercommunity.workmanager.callbackHandle"
    ) as? NSNumber else {
        return false
    }
    return FlutterCallbackCache.lookupCallbackInformation(
        handle.int64Value
    ) != nil
}

@discardableResult
private func submitBackgroundFetch(
    minutes: Int,
    earliestBeginInSeconds: TimeInterval? = nil,
    storeInterval: Bool = true,
    acceptAlreadyScheduledAsSuccess: Bool = true,
    logSubmission: Bool = true
) throws -> Date {
    let normalizedMinutes = normalizedBackgroundFetchMinutes(minutes)
    if storeInterval {
        UserDefaults.standard.set(
            normalizedMinutes,
            forKey: adaptiveBackgroundIntervalKey
        )
        UserDefaults.standard.synchronize()
    }
    let request = BGAppRefreshTaskRequest(identifier: adaptiveBackgroundTaskIdentifier)
    let delaySeconds = earliestBeginInSeconds ?? TimeInterval(normalizedMinutes * 60)
    let earliestBeginDate = Date(timeIntervalSinceNow: max(1, delaySeconds))
    request.earliestBeginDate = earliestBeginDate
    stableFetchDiagnostic(
        "BG_TASK_SUBMIT_START",
        fields: [
            "identifier": adaptiveBackgroundTaskIdentifier,
            "minutes": normalizedMinutes,
            "earliestBeginDate": stableFetchDiagnosticDate(
                earliestBeginDate
            ),
            "delayMs": Int64(max(1, delaySeconds) * 1000),
            "storeInterval": storeInterval
        ]
    )
    do {
        try BGTaskScheduler.shared.submit(request)
        stableFetchDiagnostic(
            "BG_TASK_SUBMIT_SUCCESS",
            fields: [
                "identifier": adaptiveBackgroundTaskIdentifier,
                "earliestBeginDate": stableFetchDiagnosticDate(
                    earliestBeginDate
                )
            ]
        )
        if logSubmission {
            backgroundFetchLog("Submitted BGTask earliest at \(earliestBeginDate) (~\(Int(max(0, earliestBeginDate.timeIntervalSinceNow)))s)")
        }
    } catch {
        let nsError = error as NSError
        stableFetchDiagnostic(
            "BG_TASK_SUBMIT_ERROR",
            fields: [
                "identifier": adaptiveBackgroundTaskIdentifier,
                "domain": nsError.domain,
                "code": nsError.code,
                "message": nsError.localizedDescription
            ]
        )
        if acceptAlreadyScheduledAsSuccess &&
            isAlreadyScheduledBackgroundFetchError(error) {
            backgroundFetchLog("BGTask already scheduled; keeping existing request")
            return earliestBeginDate
        }
        throw error
    }
    return earliestBeginDate
}

@discardableResult
private func submitExperimentalBackgroundWatchdog(
    minutes: Int,
    earliestBeginInSeconds: TimeInterval? = nil,
    nextDueAt: Date? = nil
) throws -> Date {
    stableFetchDiagnosticPendingRequest("beforeWatchdogSubmit")
    stableFetchDiagnostic(
        "WATCHDOG_SUBMIT_START",
        fields: [
            "minutes": normalizedBackgroundFetchMinutes(minutes),
            "requestedNextDueAt": stableFetchDiagnosticDate(nextDueAt),
            "storedNextDueAt": stableFetchDiagnosticDate(
                storedExperimentalBackgroundNextDueAt()
            ),
            "previousDeadline": stableFetchDiagnosticDate(
                storedExperimentalBackgroundWatchdogDeadline()
            )
        ]
    )
    let scheduledAt = try submitBackgroundFetch(
        minutes: minutes,
        earliestBeginInSeconds: earliestBeginInSeconds ??
            experimentalBackgroundWatchdogDelaySeconds(
                minutes: minutes,
                nextDueAt: nextDueAt
            ),
        storeInterval: false,
        acceptAlreadyScheduledAsSuccess: false,
        logSubmission: false
    )
    UserDefaults.standard.set(
        scheduledAt.timeIntervalSince1970,
        forKey: experimentalStableBackgroundWatchdogDeadlineKey
    )
    UserDefaults.standard.synchronize()
    stableFetchDiagnostic(
        "WATCHDOG_SUBMIT_SUCCESS",
        fields: [
            "scheduledAt": stableFetchDiagnosticDate(scheduledAt),
            "delayMs": Int64(scheduledAt.timeIntervalSinceNow * 1000)
        ]
    )
    stableFetchDiagnosticPendingRequest("afterWatchdogSubmit")
    return scheduledAt
}

final class AdaptiveBackgroundFetchPlugin: NSObject, FlutterPlugin {
    private static let executionLeaseLock = NSLock()
    private static var executionLeaseToken: String?
    private static var executionLeaseIssuedAt: Date?
    private static var nextExecutionEligibleAt: Date?

    private static func persistedExecutionEligibility() -> Date? {
        let timestamp = UserDefaults.standard.double(
            forKey: experimentalStableBackgroundNextExecutionEligibleAtKey
        )
        guard timestamp > 0 else { return nil }
        return Date(timeIntervalSince1970: timestamp)
    }

    private static func persistExecutionEligibility(_ date: Date?) {
        if let date {
            UserDefaults.standard.set(
                date.timeIntervalSince1970,
                forKey: experimentalStableBackgroundNextExecutionEligibleAtKey
            )
        } else {
            UserDefaults.standard.removeObject(
                forKey: experimentalStableBackgroundNextExecutionEligibleAtKey
            )
        }
        UserDefaults.standard.synchronize()
    }

    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "app.background_fetch",
            binaryMessenger: registrar.messenger()
        )
        registrar.addMethodCallDelegate(AdaptiveBackgroundFetchPlugin(), channel: channel)
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "diagnosticsEnabled":
            result(stableFetchDiagnosticsEnabled())
        case "diagnosticLog":
            guard stableFetchDiagnosticsEnabled(),
                  let arguments = call.arguments as? [String: Any],
                  let event = arguments["event"] as? String
            else {
                result(false)
                return
            }
            var fields = arguments
            fields.removeValue(forKey: "event")
            fields["origin"] = "dart"
            stableFetchDiagnostic("DART_\(event)", fields: fields)
            result(true)
        case "acquireExecution":
            result(Self.acquireExecutionLease())
        case "releaseExecution":
            guard let arguments = call.arguments as? [String: Any],
                  let token = arguments["token"] as? String
            else {
                result(false)
                return
            }
            let intervalMinutes = normalizedBackgroundFetchMinutes(
                (arguments["intervalMinutes"] as? NSNumber)?.intValue
                    ?? storedBackgroundFetchMinutes()
            )
            result(Self.releaseExecutionLease(
                token: token,
                intervalMinutes: intervalMinutes
            ))
        case "reschedule":
            handleReschedule(call, result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private static func acquireExecutionLease() -> String? {
        guard experimentalStableBackgroundFetchFlagEnabled() else {
            return ""
        }

        executionLeaseLock.lock()
        defer { executionLeaseLock.unlock() }

        let now = Date()
        if UserDefaults.standard.bool(forKey: "flutter.isAppActive") {
            stableFetchDiagnostic(
                "LEASE_ACQUIRE_DENIED",
                fields: ["reason": "appActive"]
            )
            return nil
        }
        if let activeToken = executionLeaseToken {
            if let issuedAt = executionLeaseIssuedAt,
               now.timeIntervalSince(issuedAt) >=
                    experimentalStableBackgroundExecutionLeaseMaxRuntime {
                stableFetchDiagnostic(
                    "LEASE_STALE_CLEARED",
                    fields: [
                        "token": String(activeToken.prefix(8)),
                        "issuedAt": stableFetchDiagnosticDate(issuedAt),
                        "ageMs": Int64(now.timeIntervalSince(issuedAt) * 1000)
                    ]
                )
                executionLeaseToken = nil
                executionLeaseIssuedAt = nil
            } else {
                stableFetchDiagnostic(
                    "LEASE_ACQUIRE_DENIED",
                    fields: [
                        "reason": "tokenBusy",
                        "token": String(activeToken.prefix(8)),
                        "issuedAt": stableFetchDiagnosticDate(
                            executionLeaseIssuedAt
                        )
                    ]
                )
                return nil
            }
        }
        let persistedEligibleAt = persistedExecutionEligibility()
        let eligibleAt = [nextExecutionEligibleAt, persistedEligibleAt]
            .compactMap { $0 }
            .max()
        if let eligibleAt, eligibleAt > now {
            stableFetchDiagnostic(
                "LEASE_ACQUIRE_DENIED",
                fields: [
                    "reason": "notEligibleYet",
                    "eligibleAt": stableFetchDiagnosticDate(eligibleAt),
                    "remainingMs": Int64(
                        eligibleAt.timeIntervalSince(now) * 1000
                    )
                ]
            )
            return nil
        }

        let token = UUID().uuidString
        executionLeaseToken = token
        executionLeaseIssuedAt = now
        let intervalMinutes = storedBackgroundFetchMinutes()
        let eligibleFromStart = Date(
            timeInterval: TimeInterval(intervalMinutes * 60),
            since: now
        )
        nextExecutionEligibleAt = eligibleFromStart
        persistExecutionEligibility(eligibleFromStart)
        stableFetchDiagnostic(
            "LEASE_ACQUIRED",
            fields: [
                "token": String(token.prefix(8)),
                "issuedAt": stableFetchDiagnosticDate(now),
                "eligibleAt": stableFetchDiagnosticDate(eligibleFromStart),
                "intervalMinutes": intervalMinutes
            ]
        )
        return token
    }

    private static func releaseExecutionLease(
        token: String,
        intervalMinutes: Int
    ) -> Bool {
        guard experimentalStableBackgroundFetchFlagEnabled() else {
            return true
        }

        executionLeaseLock.lock()
        defer { executionLeaseLock.unlock() }

        guard executionLeaseToken == token else {
            stableFetchDiagnostic(
                "LEASE_RELEASE_REJECTED",
                fields: [
                    "token": String(token.prefix(8)),
                    "activeToken": executionLeaseToken.map {
                        String($0.prefix(8))
                    } ?? "none"
                ]
            )
            return false
        }
        let issuedAt = executionLeaseIssuedAt
        if let issuedAt {
            let eligibleFromStart = Date(
                timeInterval: TimeInterval(intervalMinutes * 60),
                since: issuedAt
            )
            nextExecutionEligibleAt = eligibleFromStart
            persistExecutionEligibility(eligibleFromStart)
        }
        executionLeaseToken = nil
        executionLeaseIssuedAt = nil
        stableFetchDiagnostic(
            "LEASE_RELEASED",
            fields: [
                "token": String(token.prefix(8)),
                "issuedAt": stableFetchDiagnosticDate(issuedAt),
                "eligibleAt": stableFetchDiagnosticDate(
                    [nextExecutionEligibleAt, persistedExecutionEligibility()]
                        .compactMap { $0 }
                        .max()
                ),
                "intervalMinutes": intervalMinutes
            ]
        )
        return true
    }

    static func resetExecutionEligibility() {
        guard experimentalStableBackgroundFetchFlagEnabled() else { return }

        executionLeaseLock.lock()
        nextExecutionEligibleAt = nil
        persistExecutionEligibility(nil)
        stableFetchDiagnostic(
            "LEASE_ELIGIBILITY_RESET",
            fields: [
                "tokenActive": executionLeaseToken != nil,
                "tokenIssuedAt": stableFetchDiagnosticDate(
                    executionLeaseIssuedAt
                )
            ]
        )
        executionLeaseLock.unlock()
    }

    static func beginBackgroundQuiescence() {
        guard experimentalStableBackgroundFetchFlagEnabled() else { return }

        executionLeaseLock.lock()
        let quiescenceEnd = Date(
            timeIntervalSinceNow: experimentalStableBackgroundQuiescenceSeconds
        )
        if nextExecutionEligibleAt == nil ||
            nextExecutionEligibleAt! < quiescenceEnd {
            nextExecutionEligibleAt = quiescenceEnd
        }
        let persistedEligibleAt = persistedExecutionEligibility()
        if persistedEligibleAt == nil || persistedEligibleAt! < quiescenceEnd {
            persistExecutionEligibility(quiescenceEnd)
        }
        stableFetchDiagnostic(
            "LEASE_BACKGROUND_QUIESCENCE",
            fields: [
                "eligibleAt": stableFetchDiagnosticDate(
                    [nextExecutionEligibleAt, persistedExecutionEligibility()]
                        .compactMap { $0 }
                        .max()
                )
            ]
        )
        executionLeaseLock.unlock()
    }

    private func handleReschedule(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        guard let arguments = call.arguments as? [String: Any],
              let minutesNumber = arguments["minutes"] as? NSNumber
        else {
            result(FlutterMethodNotImplemented)
            return
        }
        let requestedMinutes = normalizedBackgroundFetchMinutes(
            minutesNumber.intValue
        )
        if experimentalStableBackgroundFetchFlagEnabled() {
            UserDefaults.standard.set(
                requestedMinutes,
                forKey: adaptiveBackgroundIntervalKey
            )
            UserDefaults.standard.synchronize()
            result(true)
            return
        }
        let previousMinutes = normalizedBackgroundFetchMinutes(
            (arguments["previousMinutes"] as? NSNumber)?.intValue ?? storedBackgroundFetchMinutes()
        )
        do {
            let scheduledAt = try submitBackgroundFetch(
                minutes: requestedMinutes
            )
            backgroundFetchLog("Dart requested BGTask reschedule for ~\(scheduledAt)")
            result(true)
        } catch let replacementError {
            do {
                let restoredAt = try submitBackgroundFetch(
                    minutes: previousMinutes
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

private func registerExperimentalBackgroundPlugins(
    registry: FlutterPluginRegistry
) {
    if let registrar = registry.registrar(forPlugin: "SharedPreferencesPlugin") {
        SharedPreferencesPlugin.register(with: registrar)
    }
    if let registrar = registry.registrar(
        forPlugin: "FlutterSecureStorageDarwinPlugin"
    ) {
        FlutterSecureStorageDarwinPlugin.register(with: registrar)
    }
    if let registrar = registry.registrar(forPlugin: "FPPPackageInfoPlusPlugin") {
        FPPPackageInfoPlusPlugin.register(with: registrar)
    }
    if let registrar = registry.registrar(
        forPlugin: "FlutterLocalNotificationsPlugin"
    ) {
        FlutterLocalNotificationsPlugin.register(with: registrar)
    }
    registerAdaptiveBackgroundFetchPlugin(registry: registry)
}

private final class ExperimentalBackgroundRefreshTaskSession {
    enum Ownership {
        case native
        case workmanager
        case completed
    }

    let task: BGAppRefreshTask
    let runId = UUID().uuidString
    var ownership = Ownership.native
    var didInvokeDart = false
    var readyTimeout: DispatchWorkItem?

    init(task: BGAppRefreshTask) {
        self.task = task
    }
}

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {

    private let backgroundTaskIdentifier = adaptiveBackgroundTaskIdentifier
    private let experimentalStableBackgroundFetchEnabled =
        experimentalStableBackgroundFetchFlagEnabled()

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
    private var activityNotificationChannel: FlutterMethodChannel?
    private var activityNotificationsReady = false
    private var notificationSceneActive = false
    private var pendingActivityNotificationTap: (key: String, payload: String)?
    private var deliveredActivityNotificationTapKey: String?
    private var activityNotificationTapInFlight = false
    private var experimentalStableBackgroundEngine: FlutterEngine?
    private var experimentalStableBackgroundChannel: FlutterMethodChannel?
    private var experimentalStableBackgroundReady = false
    private var experimentalStableBackgroundDesiredRunning = false
    private var experimentalWorkmanagerOnlyUntilForeground = false
    private var experimentalBackgroundLifecycleEpoch = 0
    private var experimentalLatestTimerArmId = 0
    private var experimentalBackgroundTaskSession:
        ExperimentalBackgroundRefreshTaskSession?

    private func configurePluginRegistrantCallbacks() {
        FlutterLocalNotificationsPlugin.setPluginRegistrantCallback { registry in
            GeneratedPluginRegistrant.register(with: registry)
        }
    }

    private func setupActivityNotificationChannelIfNeeded(
        binaryMessenger: FlutterBinaryMessenger
    ) {
        guard activityNotificationChannel == nil else { return }

        let channel = FlutterMethodChannel(
            name: "app.notifications",
            binaryMessenger: binaryMessenger
        )
        activityNotificationChannel = channel
        channel.setMethodCallHandler { [weak self] call, result in
            guard let self = self else {
                result(false)
                return
            }
            guard call.method == "notifications.ready" else {
                result(FlutterMethodNotImplemented)
                return
            }
            self.activityNotificationsReady = true
            result(true)
            self.flushPendingActivityNotificationTapIfReady()
        }
    }

    private func activityNotificationPayload(
        from response: UNNotificationResponse
    ) -> String? {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier,
              let payload = response.notification.request.content.userInfo["payload"] as? String
        else {
            return nil
        }

        let isActivityPayload = payload.hasPrefix("fa_activity_") ||
            payload.hasPrefix("activity_") ||
            payload.contains("DrawerIndex.Notifications") ||
            payload == "activity_native"
        let isExperimentalBackgroundPayload =
            experimentalStableBackgroundFetchEnabled &&
            (payload.hasPrefix("note_") ||
                payload.contains("DrawerIndex.Notes") ||
                payload == "note_native" ||
                payload == "app_update_available")
        return isActivityPayload || isExperimentalBackgroundPayload
            ? payload
            : nil
    }

    private func activityNotificationTapKey(
        for response: UNNotificationResponse,
        payload: String
    ) -> String {
        let notification = response.notification
        return [
            notification.request.identifier,
            String(notification.date.timeIntervalSince1970),
            response.actionIdentifier,
            payload
        ].joined(separator: "|")
    }

    @discardableResult
    private func queueActivityNotificationTap(
        _ response: UNNotificationResponse
    ) -> Bool {
        guard let payload = activityNotificationPayload(from: response) else {
            return false
        }

        let key = activityNotificationTapKey(for: response, payload: payload)
        if pendingActivityNotificationTap?.key == key ||
            deliveredActivityNotificationTapKey == key {
            return true
        }

        pendingActivityNotificationTap = (key: key, payload: payload)
        flushPendingActivityNotificationTapIfReady()
        return true
    }

    private func flushPendingActivityNotificationTapIfReady() {
        guard notificationSceneActive,
              activityNotificationsReady,
              !activityNotificationTapInFlight,
              let channel = activityNotificationChannel,
              let pendingTap = pendingActivityNotificationTap
        else {
            return
        }

        activityNotificationTapInFlight = true
        channel.invokeMethod(
            "notificationTapped",
            arguments: pendingTap.payload
        ) { [weak self] result in
            guard let self = self else { return }
            self.activityNotificationTapInFlight = false
            guard result as? Bool == true,
                  self.pendingActivityNotificationTap?.key == pendingTap.key
            else {
                return
            }
            self.pendingActivityNotificationTap = nil
            self.deliveredActivityNotificationTapKey = pendingTap.key
        }
    }

    func handleNotificationSceneConnection(
        _ connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let response = connectionOptions.notificationResponse else { return }
        _ = queueActivityNotificationTap(response)
    }

    func handleNotificationSceneDidBecomeActive() {
        notificationSceneActive = true
        flushPendingActivityNotificationTapIfReady()
    }

    func handleNotificationSceneWillResignActive() {
        notificationSceneActive = false
    }

    func handleNotificationSceneDidEnterBackground() {
        notificationSceneActive = false
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

    private func startExperimentalStableBackgroundEngineIfNeeded() {
        guard experimentalStableBackgroundFetchEnabled else {
            stableFetchDiagnostic(
                "ENGINE_START_SKIPPED",
                fields: ["reason": "experimentalDisabled"]
            )
            return
        }
        guard experimentalStableBackgroundEngine == nil else {
            stableFetchDiagnostic(
                "ENGINE_START_SKIPPED",
                fields: [
                    "reason": "alreadyStarted",
                    "ready": experimentalStableBackgroundReady
                ]
            )
            return
        }

        stableFetchDiagnostic(
            "ENGINE_START",
            fields: [
                "desiredRunning": experimentalStableBackgroundDesiredRunning,
                "workmanagerOnly": experimentalWorkmanagerOnlyUntilForeground
            ]
        )
        configurePluginRegistrantCallbacks()
        let engine = FlutterEngine(
            name: "FAExperimentalStableBackgroundFetch",
            project: nil,
            allowHeadlessExecution: true
        )
        experimentalStableBackgroundEngine = engine

        guard engine.run(
            withEntrypoint: experimentalStableBackgroundFetchEntrypoint
        ) else {
            stableFetchDiagnostic("ENGINE_RUN_FAILED")
            experimentalStableBackgroundEngine = nil
            return
        }
        stableFetchDiagnostic("ENGINE_RUN_SUCCEEDED")
        registerExperimentalBackgroundPlugins(registry: engine)
        let channel = FlutterMethodChannel(
            name: experimentalStableBackgroundFetchChannelName,
            binaryMessenger: engine.binaryMessenger
        )
        channel.setMethodCallHandler { [weak self] call, result in
            DispatchQueue.main.async {
                guard let self else {
                    result(false)
                    return
                }
                self.handleExperimentalStableBackgroundCall(
                    call,
                    result: result
                )
            }
        }
        experimentalStableBackgroundChannel = channel
        stableFetchDiagnostic("ENGINE_CHANNEL_READY")
    }

    private func handleExperimentalStableBackgroundCall(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        switch call.method {
        case "ready":
            guard let arguments = call.arguments as? [String: Any],
                  (arguments["protocolVersion"] as? NSNumber)?.intValue == 1
            else {
                result(FlutterMethodNotImplemented)
                return
            }

            experimentalStableBackgroundReady = true
            stableFetchDiagnostic(
                "ENGINE_DART_READY",
                fields: [
                    "desiredRunning": experimentalStableBackgroundDesiredRunning,
                    "workmanagerOnly": experimentalWorkmanagerOnlyUntilForeground,
                    "lifecycleEpoch": experimentalBackgroundLifecycleEpoch
                ]
            )
            result([
                "protocolVersion": 1,
                "isInBackground": experimentalStableBackgroundDesiredRunning,
                "lifecycleEpoch": experimentalBackgroundLifecycleEpoch,
                "diagnosticsEnabled": stableFetchDiagnosticsEnabled()
            ])
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      let session = self.experimentalBackgroundTaskSession
                else {
                    return
                }
                self.routeExperimentalBackgroundTaskToDart(session)
            }
        case "timerArmed":
            guard let arguments = call.arguments as? [String: Any],
                  let nextDueAtNumber = arguments["nextDueAtMs"] as? NSNumber,
                  let intervalNumber = arguments["intervalMinutes"] as? NSNumber,
                  let armIdNumber = arguments["armId"] as? NSNumber,
                  let lifecycleEpochNumber = arguments["lifecycleEpoch"] as? NSNumber
            else {
                result(false)
                return
            }
            let armId = armIdNumber.intValue
            let lifecycleEpoch = lifecycleEpochNumber.intValue
            let nextDueAt = Date(
                timeIntervalSince1970: nextDueAtNumber.doubleValue / 1000
            )
            stableFetchDiagnostic(
                "WATCHDOG_TIMER_ARM_RECEIVED",
                fields: [
                    "armId": armId,
                    "lifecycleEpoch": lifecycleEpoch,
                    "nativeLifecycleEpoch": experimentalBackgroundLifecycleEpoch,
                    "nextDueAt": stableFetchDiagnosticDate(nextDueAt),
                    "intervalMinutes": intervalNumber.intValue,
                    "desiredRunning": experimentalStableBackgroundDesiredRunning,
                    "workmanagerOnly": experimentalWorkmanagerOnlyUntilForeground,
                    "latestAcceptedArmId": experimentalLatestTimerArmId
                ]
            )
            guard lifecycleEpoch == experimentalBackgroundLifecycleEpoch else {
                stableFetchDiagnostic(
                    "WATCHDOG_TIMER_ARM_IGNORED",
                    fields: ["reason": "lifecycleEpochMismatch", "armId": armId]
                )
                result(true)
                return
            }
            if armId <= experimentalLatestTimerArmId {
                stableFetchDiagnostic(
                    "WATCHDOG_TIMER_ARM_IGNORED",
                    fields: ["reason": "staleArmId", "armId": armId]
                )
                result(true)
                return
            }
            guard experimentalStableBackgroundDesiredRunning,
                  !experimentalWorkmanagerOnlyUntilForeground
            else {
                stableFetchDiagnostic(
                    "WATCHDOG_TIMER_ARM_IGNORED",
                    fields: ["reason": "notBackgroundOwner", "armId": armId]
                )
                result(true)
                return
            }
            do {
                let scheduledAt = try submitExperimentalBackgroundWatchdog(
                    minutes: intervalNumber.intValue,
                    nextDueAt: nextDueAt
                )
                experimentalLatestTimerArmId = armId
                stableFetchDiagnostic(
                    "WATCHDOG_TIMER_ARM_ACCEPTED",
                    fields: [
                        "armId": armId,
                        "scheduledAt": stableFetchDiagnosticDate(scheduledAt)
                    ]
                )
                result(true)
            } catch {
                let nsError = error as NSError
                stableFetchDiagnostic(
                    "WATCHDOG_TIMER_ARM_FAILED",
                    fields: [
                        "armId": armId,
                        "domain": nsError.domain,
                        "code": nsError.code,
                        "message": nsError.localizedDescription
                    ]
                )
                result(FlutterError(
                    code: "experimental_watchdog_schedule_failed",
                    message: error.localizedDescription,
                    details: nil
                ))
            }
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func updateExperimentalStableBackgroundLifecycle(
        isInBackground: Bool,
        source: String
    ) {
        guard experimentalStableBackgroundFetchEnabled else { return }

        experimentalBackgroundLifecycleEpoch &+= 1
        experimentalLatestTimerArmId = 0
        experimentalStableBackgroundDesiredRunning = isInBackground
        stableFetchDiagnostic(
            "LIFECYCLE_UPDATE",
            fields: [
                "isInBackground": isInBackground,
                "source": source,
                "lifecycleEpoch": experimentalBackgroundLifecycleEpoch,
                "engineReady": experimentalStableBackgroundReady,
                "workmanagerOnly": experimentalWorkmanagerOnlyUntilForeground
            ].merging(stableFetchDiagnosticSnapshot()) { current, _ in current }
        )
        if isInBackground {
            startExperimentalStableBackgroundEngineIfNeeded()
        }
        guard experimentalStableBackgroundReady,
              let channel = experimentalStableBackgroundChannel
        else {
            return
        }

        if isInBackground {
            channel.invokeMethod(
                "start",
                arguments: [
                    "source": source,
                    "intervalMinutes": storedBackgroundFetchMinutes(),
                    "lifecycleEpoch": experimentalBackgroundLifecycleEpoch
                ]
            )
        } else {
            channel.invokeMethod(
                "stop",
                arguments: [
                    "source": source,
                    "lifecycleEpoch": experimentalBackgroundLifecycleEpoch
                ]
            )
        }
    }

    private func handleExperimentalBackgroundFetch(
        _ refreshTask: BGAppRefreshTask
    ) {
        stableFetchDiagnostic(
            "BG_TASK_CALLBACK",
            fields: [
                "storedDeadline": stableFetchDiagnosticDate(
                    storedExperimentalBackgroundWatchdogDeadline()
                ),
                "desiredRunning": experimentalStableBackgroundDesiredRunning,
                "engineReady": experimentalStableBackgroundReady,
                "workmanagerOnly": experimentalWorkmanagerOnlyUntilForeground,
                "lifecycleEpoch": experimentalBackgroundLifecycleEpoch
            ].merging(stableFetchDiagnosticSnapshot()) { current, _ in current }
        )
        if let deadline = storedExperimentalBackgroundWatchdogDeadline() {
            let remaining = deadline.timeIntervalSinceNow
            if remaining > 1 {
                stableFetchDiagnostic(
                    "BG_TASK_COMPLETED_EARLY",
                    fields: [
                        "reason": "beforeStoredDeadline",
                        "remainingMs": Int64(remaining * 1000)
                    ]
                )
                refreshTask.setTaskCompleted(success: true)
                return
            }
        }

        if let current = experimentalBackgroundTaskSession,
           current.ownership == .native {
            scheduleBackgroundFetch(
                asSoonAsPossible: false,
                watchdog: true,
                watchdogFromNow: true,
                source: "experimentalConcurrentBGTask"
            )
            stableFetchDiagnostic(
                "BG_TASK_COMPLETED_EARLY",
                fields: ["reason": "concurrentNativeSession"]
            )
            refreshTask.setTaskCompleted(success: false)
            return
        }

        let session = ExperimentalBackgroundRefreshTaskSession(
            task: refreshTask
        )
        experimentalBackgroundTaskSession = session
        stableFetchDiagnostic(
            "BG_TASK_SESSION_CREATED",
            fields: ["runId": session.runId]
        )
        refreshTask.expirationHandler = { [weak self, weak session] in
            DispatchQueue.main.async {
                guard let self, let session else { return }
                stableFetchDiagnostic(
                    "BG_TASK_EXPIRED",
                    fields: ["runId": session.runId]
                )
                self.completeExperimentalBackgroundTask(
                    session,
                    success: false
                )
            }
        }

        scheduleBackgroundFetch(
            asSoonAsPossible: false,
            watchdog: true,
            watchdogFromNow: true,
            source: "experimentalBGTask"
        )
        startExperimentalStableBackgroundEngineIfNeeded()
        if experimentalStableBackgroundReady {
            stableFetchDiagnostic(
                "BG_TASK_ROUTE_SELECTED",
                fields: ["route": "persistentEngine", "runId": session.runId]
            )
            routeExperimentalBackgroundTaskToDart(session)
            return
        }

        let timeout = DispatchWorkItem { [weak self, weak session] in
            guard let self, let session else { return }
            stableFetchDiagnostic(
                "BG_TASK_ENGINE_READY_TIMEOUT",
                fields: ["runId": session.runId]
            )
            self.handOffExperimentalBackgroundTaskToWorkmanager(session)
        }
        session.readyTimeout = timeout
        DispatchQueue.main.asyncAfter(
            deadline: .now() + experimentalStableBackgroundFetchReadyTimeout,
            execute: timeout
        )
    }

    private func handleExperimentalWorkmanagerBackgroundFetch(
        _ refreshTask: BGAppRefreshTask
    ) {
        stableFetchDiagnostic(
            "BG_TASK_ROUTE_SELECTED",
            fields: ["route": "workmanagerColdLaunch"]
        )
        experimentalStableBackgroundDesiredRunning = false
        clearExperimentalBackgroundWatchdogDeadline()
        let minutes = storedBackgroundFetchMinutes()
        WorkmanagerPlugin.handlePeriodicTask(
            identifier: backgroundTaskIdentifier,
            task: refreshTask,
            earliestBeginInSeconds: Double(minutes * 60)
        )
    }

    private func routeExperimentalBackgroundTaskToDart(
        _ session: ExperimentalBackgroundRefreshTaskSession
    ) {
        guard let current = experimentalBackgroundTaskSession,
              current === session,
              session.ownership == .native,
              !session.didInvokeDart,
              experimentalStableBackgroundReady,
              let channel = experimentalStableBackgroundChannel
        else {
            return
        }

        session.didInvokeDart = true
        session.readyTimeout?.cancel()
        session.readyTimeout = nil
        stableFetchDiagnostic(
            "BG_TASK_DART_RUN_NOW",
            fields: ["runId": session.runId]
        )
        channel.invokeMethod(
            "runNow",
            arguments: [
                "runId": session.runId,
                "source": "systemBGTask"
            ]
        ) { [weak self, weak session] response in
            DispatchQueue.main.async {
                guard let self, let session,
                      session.ownership == .native
                else {
                    return
                }
                let responseMap = response as? [String: Any]
                let returnedRunId = responseMap?["runId"] as? String
                let success: Bool
                if let boolValue = responseMap?["success"] as? Bool {
                    success = boolValue
                } else {
                    success = (responseMap?["success"] as? NSNumber)?.boolValue
                        ?? false
                }
                stableFetchDiagnostic(
                    "BG_TASK_DART_RESULT",
                    fields: [
                        "runId": session.runId,
                        "returnedRunId": returnedRunId ?? "none",
                        "success": success
                    ]
                )
                self.completeExperimentalBackgroundTask(
                    session,
                    success: returnedRunId == session.runId && success
                )
            }
        }
    }

    private func handOffExperimentalBackgroundTaskToWorkmanager(
        _ session: ExperimentalBackgroundRefreshTaskSession
    ) {
        guard let current = experimentalBackgroundTaskSession,
              current === session,
              session.ownership == .native,
              !session.didInvokeDart
        else {
            return
        }
        guard workmanagerBackgroundCallbackIsAvailable() else {
            stableFetchDiagnostic(
                "BG_TASK_HANDOFF_FAILED",
                fields: [
                    "reason": "callbackUnavailable",
                    "runId": session.runId
                ]
            )
            completeExperimentalBackgroundTask(session, success: false)
            return
        }

        session.ownership = .workmanager
        session.readyTimeout?.cancel()
        session.readyTimeout = nil
        session.task.expirationHandler = nil
        experimentalBackgroundTaskSession = nil
        experimentalWorkmanagerOnlyUntilForeground = true
        experimentalStableBackgroundDesiredRunning = false
        stableFetchDiagnostic(
            "BG_TASK_ROUTE_SELECTED",
            fields: [
                "route": "workmanagerReadyTimeout",
                "runId": session.runId
            ]
        )
        experimentalStableBackgroundChannel?.invokeMethod(
            "stop",
            arguments: ["source": "workmanagerFallback"]
        )
        clearExperimentalBackgroundWatchdogDeadline()
        let minutes = storedBackgroundFetchMinutes()
        WorkmanagerPlugin.handlePeriodicTask(
            identifier: backgroundTaskIdentifier,
            task: session.task,
            earliestBeginInSeconds: Double(minutes * 60)
        )
    }

    private func completeExperimentalBackgroundTask(
        _ session: ExperimentalBackgroundRefreshTaskSession,
        success: Bool
    ) {
        guard session.ownership == .native else { return }

        session.ownership = .completed
        session.readyTimeout?.cancel()
        session.readyTimeout = nil
        session.task.expirationHandler = nil
        if let current = experimentalBackgroundTaskSession,
           current === session {
            experimentalBackgroundTaskSession = nil
        }
        stableFetchDiagnostic(
            "BG_TASK_COMPLETED",
            fields: [
                "runId": session.runId,
                "success": success
            ]
        )
        session.task.setTaskCompleted(success: success)
    }

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {

        fLog("Application launching...")
        let launchedDirectlyIntoBackground =
            application.applicationState == .background
        experimentalWorkmanagerOnlyUntilForeground =
            experimentalStableBackgroundFetchEnabled &&
            launchedDirectlyIntoBackground
        experimentalStableBackgroundDesiredRunning =
            launchedDirectlyIntoBackground &&
            !experimentalWorkmanagerOnlyUntilForeground
        stableFetchDiagnostic(
            "APP_LAUNCH",
            fields: [
                "applicationState": application.applicationState.rawValue,
                "launchedDirectlyIntoBackground": launchedDirectlyIntoBackground,
                "experimentalEnabled": experimentalStableBackgroundFetchEnabled,
                "diagnosticsEnabled": stableFetchDiagnosticsEnabled(),
                "workmanagerOnly": experimentalWorkmanagerOnlyUntilForeground,
                "tracePath": stableFetchDiagnosticTraceURL.path
            ].merging(stableFetchDiagnosticSnapshot()) { current, _ in current }
        )
        UserDefaults.standard.set(
            experimentalStableBackgroundFetchEnabled,
            forKey: experimentalStableBackgroundFetchPreferenceKey
        )
        UserDefaults.standard.synchronize()

        if application.applicationState == .background {
            fLog("Background launch detected - skipping FlutterEngine.run for UI entrypoint")
            if experimentalStableBackgroundFetchEnabled {
                setFlutterSharedBool(false, forKey: "isAppActive")
            }
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
            stableFetchDiagnostic(
                "BG_TASK_LAUNCH_HANDLER",
                fields: [
                    "identifier": task.identifier,
                    "applicationState": UIApplication.shared.applicationState.rawValue
                ]
            )
            self.fLog("===============================================")
            self.fLog("BACKGROUND TASK TRIGGERED BY iOS (\(task.identifier))")
            self.fLog("Time: \(Date())")
            self.fLog("===============================================")
            self.handleBackgroundFetch(task: task)
        }

        if experimentalStableBackgroundFetchEnabled {
            if !launchedDirectlyIntoBackground {
                BGTaskScheduler.shared.cancel(
                    taskRequestWithIdentifier: backgroundTaskIdentifier
                )
                clearExperimentalBackgroundWatchdogDeadline()
            }
        } else {
            scheduleBackgroundFetch(
                asSoonAsPossible: false,
                source: "didFinishLaunching"
            )
        }
        getPendingBackgroundTasks()
        logApproxNextFetch("didFinishLaunching")

        self.fLog("Application initialization complete")
        self.fLog("Background task identifier: \(backgroundTaskIdentifier)")

        let didFinish = super.application(
            application,
            didFinishLaunchingWithOptions: launchOptions
        )
        return didFinish
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
        setupActivityNotificationChannelIfNeeded(
            binaryMessenger: engineBridge.applicationRegistrar.messenger()
        )
    }

    func handleDidEnterBackground(source: String) {
        fLog("App entering background (\(source))")
        stableFetchDiagnostic(
            "APP_DID_ENTER_BACKGROUND",
            fields: [
                "source": source,
                "lifecycleEpoch": experimentalBackgroundLifecycleEpoch,
                "engineReady": experimentalStableBackgroundReady,
                "workmanagerOnly": experimentalWorkmanagerOnlyUntilForeground
            ].merging(stableFetchDiagnosticSnapshot()) { current, _ in current }
        )
        setFlutterSharedBool(false, forKey: "isAppActive")
        AdaptiveBackgroundFetchPlugin.beginBackgroundQuiescence()
        if experimentalStableBackgroundFetchEnabled {
            if !experimentalWorkmanagerOnlyUntilForeground {
                updateExperimentalStableBackgroundLifecycle(
                    isInBackground: true,
                    source: source
                )
                scheduleBackgroundFetch(
                    asSoonAsPossible: false,
                    watchdog: true,
                    source: "didEnterBackground:\(source)"
                )
            }
        } else {
            scheduleBackgroundFetch(
                asSoonAsPossible: false,
                source: "didEnterBackground:\(source)"
            )
        }
        logApproxNextFetch("didEnterBackground:\(source)")
    }

    func handleExperimentalWillBecomeActive(source: String) {
        guard experimentalStableBackgroundFetchEnabled else { return }

        stableFetchDiagnostic(
            "APP_WILL_BECOME_ACTIVE",
            fields: ["source": source]
        )
        setFlutterSharedBool(true, forKey: "isAppActive")
        AdaptiveBackgroundFetchPlugin.resetExecutionEligibility()
        updateExperimentalStableBackgroundLifecycle(
            isInBackground: false,
            source: source
        )
    }

    func handleDidBecomeActive(source: String) {
        fLog("App became active (\(source))")
        stableFetchDiagnostic(
            "APP_DID_BECOME_ACTIVE",
            fields: [
                "source": source,
                "lifecycleEpoch": experimentalBackgroundLifecycleEpoch
            ].merging(stableFetchDiagnosticSnapshot()) { current, _ in current }
        )
        experimentalWorkmanagerOnlyUntilForeground = false
        setFlutterSharedBool(true, forKey: "isAppActive")
        AdaptiveBackgroundFetchPlugin.resetExecutionEligibility()
        updateExperimentalStableBackgroundLifecycle(
            isInBackground: false,
            source: source
        )
        UserDefaults.standard.set(0, forKey: adaptiveBackgroundEmptyStreakKey)
        if experimentalStableBackgroundFetchEnabled {
            UserDefaults.standard.set(15, forKey: adaptiveBackgroundIntervalKey)
            UserDefaults.standard.synchronize()
            BGTaskScheduler.shared.cancel(
                taskRequestWithIdentifier: backgroundTaskIdentifier
            )
            clearExperimentalBackgroundWatchdogDeadline()
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      UIApplication.shared.applicationState == .active
                else {
                    return
                }
                self.startExperimentalStableBackgroundEngineIfNeeded()
            }
        } else {
            do {
                let scheduledAt = try submitBackgroundFetch(
                    minutes: 15
                )
                fLog("Background fetch reset to 15m after app became active: \(scheduledAt)")
            } catch {
                fLog("Failed to reset background fetch after app became active: \(error.localizedDescription)")
            }
        }
        getPendingBackgroundTasks()
        logApproxNextFetch("didBecomeActive:\(source)")
    }

    private func handleBackgroundFetch(task: BGTask) {
        fLog("handleBackgroundFetch started")
        stableFetchDiagnostic(
            "BG_TASK_HANDLE_START",
            fields: [
                "identifier": task.identifier,
                "experimentalEnabled": experimentalStableBackgroundFetchEnabled,
                "workmanagerOnly": experimentalWorkmanagerOnlyUntilForeground,
                "applicationState": UIApplication.shared.applicationState.rawValue
            ]
        )
        if let refreshTask = task as? BGAppRefreshTask {
            if experimentalStableBackgroundFetchEnabled {
                if experimentalWorkmanagerOnlyUntilForeground {
                    handleExperimentalWorkmanagerBackgroundFetch(refreshTask)
                    return
                }
                DispatchQueue.main.async { [weak self] in
                    self?.handleExperimentalBackgroundFetch(refreshTask)
                }
                return
            }
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
        watchdog: Bool = false,
        watchdogFromNow: Bool = false,
        source: String
    ) {
        let minutes = storedBackgroundFetchMinutes()
        stableFetchDiagnostic(
            "BG_TASK_SCHEDULE_REQUEST",
            fields: [
                "source": source,
                "minutes": minutes,
                "asSoonAsPossible": asSoonAsPossible,
                "watchdog": watchdog,
                "watchdogFromNow": watchdogFromNow
            ].merging(stableFetchDiagnosticSnapshot()) { current, _ in current }
        )
        do {
            let scheduledAt: Date
            if watchdog {
                scheduledAt = try submitExperimentalBackgroundWatchdog(
                    minutes: minutes,
                    earliestBeginInSeconds: watchdogFromNow
                        ? TimeInterval(minutes * 60) +
                            experimentalStableBackgroundWatchdogGraceSeconds
                        : nil
                )
            } else {
                scheduledAt = try submitBackgroundFetch(
                    minutes: minutes,
                    earliestBeginInSeconds: asSoonAsPossible
                        ? adaptiveBackgroundAsapSeconds
                        : nil
                )
            }
            let mode: String
            if asSoonAsPossible {
                mode = "ASAP"
            } else if watchdog {
                mode = watchdogFromNow
                    ? "\(minutes + 5)m watchdog"
                    : "timer-deadline watchdog"
            } else {
                mode = "\(minutes)m"
            }
            fLog("Background fetch scheduled from \(source) with \(mode) earliest request: \(scheduledAt)")
            stableFetchDiagnostic(
                "BG_TASK_SCHEDULED",
                fields: [
                    "source": source,
                    "mode": mode,
                    "scheduledAt": stableFetchDiagnosticDate(scheduledAt)
                ]
            )
            logApproxNextFetch("after submit")
        } catch {
            let errorString = error.localizedDescription
            let nsError = error as NSError
            stableFetchDiagnostic(
                "BG_TASK_SCHEDULE_FAILED",
                fields: [
                    "source": source,
                    "domain": nsError.domain,
                    "code": nsError.code,
                    "message": nsError.localizedDescription
                ]
            )
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
        if queueActivityNotificationTap(response) {
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
