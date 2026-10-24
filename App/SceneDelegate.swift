import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let window = UIWindow(windowScene: windowScene)
        let ffmpeg = FFMpegViewController()
        ffmpeg.tabBarItem = UITabBarItem(title: "FFmpeg", image: UIImage(systemName: "play.rectangle"), tag: 0)
        let webp = WebPViewController()
        webp.tabBarItem = UITabBarItem(title: "WebP", image: UIImage(systemName: "photo.on.rectangle"), tag: 1)
        let tabs = UITabBarController()
        tabs.viewControllers = [ffmpeg, webp]
        window.rootViewController = tabs
        self.window = window
        window.makeKeyAndVisible()
    }
}
