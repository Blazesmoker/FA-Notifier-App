import UIKit
import Flutter

private func sceneLog(_ msg: String) {
    let line = "[SceneDelegate] \(msg)"
    NSLog("%@", line)
    debugPrint("flutter: \(line)")
}

@available(iOS 13.0, *)
class SceneDelegate: UIResponder, UIWindowSceneDelegate, FlutterSceneLifeCycleProvider {
    let sceneLifeCycleDelegate = FlutterPluginSceneLifeCycleDelegate()

    var window: UIWindow?
    private var pendingWindowScene: UIWindowScene?
    private var pendingSession: UISceneSession?
    private var pendingConnectionOptions: UIScene.ConnectionOptions?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }

        pendingWindowScene = windowScene
        pendingSession = session
        pendingConnectionOptions = connectionOptions

        if UIApplication.shared.applicationState == .background &&
            connectionOptions.notificationResponse == nil {
            return
        }

        createWindow(using: windowScene)
        forwardSceneConnection(scene, session: session, options: connectionOptions)
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        if let engine = (UIApplication.shared.delegate as? AppDelegate)?.flutterEngine {
            sceneLifeCycleDelegate.unregisterSceneLifeCycle(with: engine)
        }
        sceneLifeCycleDelegate.sceneDidDisconnect(scene)
        if let windowScene = window?.windowScene, scene === windowScene {
            window = nil
        }
        if let pendingWindowScene = self.pendingWindowScene, scene === pendingWindowScene {
            self.pendingWindowScene = nil
            pendingSession = nil
            pendingConnectionOptions = nil
        }
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        createWindowAndForwardPendingConnectionIfNeeded(for: scene)
        sceneLifeCycleDelegate.sceneWillEnterForeground(scene)
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        createWindowAndForwardPendingConnectionIfNeeded(for: scene)

        sceneLifeCycleDelegate.sceneDidBecomeActive(scene)

        if let appDelegate = UIApplication.shared.delegate as? AppDelegate {
            appDelegate.handleDidBecomeActive(source: "sceneDelegate")
        } else {
            sceneLog("AppDelegate unavailable during sceneDidBecomeActive")
        }
    }

    func sceneWillResignActive(_ scene: UIScene) {
        sceneLifeCycleDelegate.sceneWillResignActive(scene)
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        sceneLifeCycleDelegate.sceneDidEnterBackground(scene)

        if let appDelegate = UIApplication.shared.delegate as? AppDelegate {
            appDelegate.handleDidEnterBackground(source: "sceneDelegate")
        } else {
            sceneLog("AppDelegate unavailable during sceneDidEnterBackground")
        }
    }

    func scene(
        _ scene: UIScene,
        openURLContexts URLContexts: Set<UIOpenURLContext>
    ) {
        sceneLifeCycleDelegate.scene(scene, openURLContexts: URLContexts)
    }

    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        sceneLifeCycleDelegate.scene(scene, continue: userActivity)
    }

    func windowScene(
        _ windowScene: UIWindowScene,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        sceneLifeCycleDelegate.windowScene(
            windowScene,
            performActionFor: shortcutItem,
            completionHandler: completionHandler
        )
    }

    private func createWindow(using windowScene: UIWindowScene) {
        let window = UIWindow(windowScene: windowScene)

        let appDelegate = UIApplication.shared.delegate as? AppDelegate
        let flutterVC: FlutterViewController
        if let engine = appDelegate?.flutterEngine {
            sceneLifeCycleDelegate.registerSceneLifeCycle(with: engine)
            flutterVC = FlutterViewController(engine: engine, nibName: nil, bundle: nil)
        } else {
            let engine = FlutterEngine(name: "shared_engine")
            engine.run()
            appDelegate?.flutterEngine = engine
            GeneratedPluginRegistrant.register(with: engine)
            sceneLifeCycleDelegate.registerSceneLifeCycle(with: engine)
            flutterVC = FlutterViewController(engine: engine, nibName: nil, bundle: nil)
        }

        window.rootViewController = flutterVC
        self.window = window
        window.makeKeyAndVisible()

        appDelegate?.setupNotificationChannelIfNeeded()
        appDelegate?.setupTranslationChannelIfNeeded()
        pendingWindowScene = nil
        pendingSession = nil
        pendingConnectionOptions = nil
    }

    private func createWindowAndForwardPendingConnectionIfNeeded(for scene: UIScene) {
        guard window == nil else { return }
        guard let windowScene = (scene as? UIWindowScene) ?? pendingWindowScene else { return }

        let session = pendingSession
        let options = pendingConnectionOptions
        createWindow(using: windowScene)
        if let session = session,
           let options = options {
            forwardSceneConnection(scene, session: session, options: options)
        }
    }

    private func forwardSceneConnection(
        _ scene: UIScene,
        session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        sceneLifeCycleDelegate.scene(
            scene,
            willConnectTo: session,
            options: connectionOptions
        )
    }
}
