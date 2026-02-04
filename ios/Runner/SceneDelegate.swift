import UIKit
import Flutter

@available(iOS 13.0, *)
class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var pendingWindowScene: UIWindowScene?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }

    
        pendingWindowScene = windowScene

        
        if UIApplication.shared.applicationState == .background {
            return
        }

      
        createWindow(using: windowScene)
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
    
        if window == nil {
            if let ws = (scene as? UIWindowScene) ?? pendingWindowScene {
                createWindow(using: ws)
            }
        }
    }

    private func createWindow(using windowScene: UIWindowScene) {
        let window = UIWindow(windowScene: windowScene)

        let appDelegate = UIApplication.shared.delegate as? AppDelegate
        let flutterVC: FlutterViewController
        if let engine = appDelegate?.flutterEngine {
            flutterVC = FlutterViewController(engine: engine, nibName: nil, bundle: nil)
        } else {
            let engine = FlutterEngine(name: "shared_engine")
            engine.run()
            appDelegate?.flutterEngine = engine
            GeneratedPluginRegistrant.register(with: engine)
            flutterVC = FlutterViewController(engine: engine, nibName: nil, bundle: nil)
        }

        window.rootViewController = flutterVC
        self.window = window
        window.makeKeyAndVisible()

        appDelegate?.setupNotificationChannelIfNeeded()
        pendingWindowScene = nil
    }
}
