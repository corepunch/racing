import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        window = UIWindow(frame: UIScreen.main.bounds)
        window?.rootViewController = TrackVideoRecorder.runFromLaunchArguments()
            ? UIViewController() : MenuNavigationController(rootViewController: MenuViewController())
        window?.makeKeyAndVisible()
        return true
    }
}

/// Menus push and pop with the system slide; the bar is hidden because every screen draws
/// its own header, and the edge swipe still goes back.
final class MenuNavigationController: UINavigationController, UIGestureRecognizerDelegate {
    override func viewDidLoad() {
        super.viewDidLoad()
        setNavigationBarHidden(true, animated: false)
        interactivePopGestureRecognizer?.delegate = self
        overrideUserInterfaceStyle = .dark
    }

    func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool { viewControllers.count > 1 }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .portrait }
    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var childForStatusBarHidden: UIViewController? { topViewController }
}
