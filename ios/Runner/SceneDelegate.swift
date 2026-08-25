import Flutter
import UIKit

@available(iOS 13.0, *)
class SceneDelegate: FlutterSceneDelegate {
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
