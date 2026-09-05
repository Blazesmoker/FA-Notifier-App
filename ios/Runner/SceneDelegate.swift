import Flutter
import UIKit
import UserNotifications

@available(iOS 13.0, *)
class SceneDelegate: FlutterSceneDelegate {
    override func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        super.scene(scene, willConnectTo: session, options: connectionOptions)
        if let response = connectionOptions.notificationResponse,
           let appDelegate = UIApplication.shared.delegate as? AppDelegate {
            appDelegate.userNotificationCenter(
                UNUserNotificationCenter.current(),
                didReceive: response,
                withCompletionHandler: {}
            )
        }
    }

    override func sceneDidBecomeActive(_ scene: UIScene) {
        super.sceneDidBecomeActive(scene)

        if let appDelegate = UIApplication.shared.delegate as? AppDelegate {
            appDelegate.handleDidBecomeActive(source: "sceneDelegate")
        }
    }

    override func sceneDidEnterBackground(_ scene: UIScene) {
        super.sceneDidEnterBackground(scene)

        if let appDelegate = UIApplication.shared.delegate as? AppDelegate {
            appDelegate.handleDidEnterBackground(source: "sceneDelegate")
        }
    }
}
