import Flutter
import UIKit

@available(iOS 13.0, *)
class SceneDelegate: FlutterSceneDelegate {
    override func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        super.scene(
            scene,
            willConnectTo: session,
            options: connectionOptions
        )
        if let appDelegate = UIApplication.shared.delegate as? AppDelegate {
            appDelegate.handleNotificationSceneConnection(connectionOptions)
        }
    }

    override func sceneDidBecomeActive(_ scene: UIScene) {
        if let appDelegate = UIApplication.shared.delegate as? AppDelegate {
            appDelegate.handleExperimentalWillBecomeActive(
                source: "sceneDelegate.preSuper"
            )
        }
        super.sceneDidBecomeActive(scene)

        if let appDelegate = UIApplication.shared.delegate as? AppDelegate {
            appDelegate.handleNotificationSceneDidBecomeActive()
            appDelegate.handleDidBecomeActive(source: "sceneDelegate")
        }
    }

    override func sceneWillResignActive(_ scene: UIScene) {
        super.sceneWillResignActive(scene)

        if let appDelegate = UIApplication.shared.delegate as? AppDelegate {
            appDelegate.handleNotificationSceneWillResignActive()
        }
    }

    override func sceneDidEnterBackground(_ scene: UIScene) {
        super.sceneDidEnterBackground(scene)

        if let appDelegate = UIApplication.shared.delegate as? AppDelegate {
            appDelegate.handleNotificationSceneDidEnterBackground()
            appDelegate.handleDidEnterBackground(source: "sceneDelegate")
        }
    }
}
