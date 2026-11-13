import UIKit
import SceneKit
import SpriteKit

final class GameViewController: UIViewController {

    private var scnView: SCNView!
    private var gameScene: GameScene!
    private var hudScene: HUDScene!
    private var controlsView: InputView!
    private var hudTimer: Timer?

    override func viewDidLoad() {
        super.viewDidLoad()

        // ── SceneKit view ─────────────────────────────────────────────────────
        scnView = SCNView(frame: view.bounds)
        scnView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(scnView)

        let loading = UILabel(frame: view.bounds)
        loading.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        loading.backgroundColor = .black
        loading.textColor = .white
        loading.textAlignment = .center
        loading.font = .systemFont(ofSize: 24, weight: .semibold)
        loading.text = "Preparing track…"
        view.addSubview(loading)

        // Launch arguments: `-track <0...3>` picks a circuit, `-seed <n>` generates a new one,
        // `-autoDrive YES` runs the demo.
        let trackIndex = UserDefaults.standard.integer(forKey: "track")
        let seed = UserDefaults.standard.integer(forKey: "seed")
        let definition = seed > 0
            ? TrackLibrary.generated(seed: UInt64(seed))
            : TrackLibrary.all[min(max(trackIndex, 0), TrackLibrary.all.count - 1)]
        let autoDrive = UserDefaults.standard.bool(forKey: "autoDrive")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let scene = GameScene(definition: definition)
            scene.autoDrive = autoDrive
            scene.selfDrive = UserDefaults.standard.bool(forKey: "selfDrive")
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.installScene(scene)
                loading.removeFromSuperview()
            }
        }
    }

    private func installScene(_ scene: GameScene) {
        gameScene = scene
        scnView.scene     = gameScene.scene
        scnView.delegate  = gameScene
        scnView.isPlaying = true
        scnView.preferredFramesPerSecond = 60
        scnView.antialiasingMode         = .none
        scnView.showsStatistics          = false   // flip to true while tuning

        // ── SpriteKit HUD overlay ─────────────────────────────────────────────
        let hudSize = view.bounds.size
        hudScene    = HUDScene(size: hudSize)
        hudScene.gameScene  = gameScene
        hudScene.scaleMode  = .resizeFill
        hudScene.buildMinimapPath(trackPath: gameScene.track)
        scnView.overlaySKScene = hudScene

        // ── Touch and keyboard controls ───────────────────────────────────────
        controlsView = InputView(frame: view.bounds)
        controlsView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(controlsView)
        controlsView.becomeFirstResponder()
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(suspend),
                           name: UIApplication.willResignActiveNotification, object: nil)
        center.addObserver(self, selector: #selector(suspend),
                           name: UIApplication.didEnterBackgroundNotification, object: nil)
        center.addObserver(self, selector: #selector(resume),
                           name: UIApplication.didBecomeActiveNotification, object: nil)
        // The scene can finish building after the app has already left the foreground.
        if UIApplication.shared.applicationState != .active { suspend() }

        // ── HUD polling timer ─────────────────────────────────────────────────
        hudTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.pollHUD()
        }
    }

    private func pollHUD() {
        guard let gs = gameScene, let hud = hudScene else { return }
        gs.steerInput = controlsView.steer
        gs.brakeInput = controlsView.brake
        gs.throttleInput = controlsView.throttle
        hud.updateHUD(
            speed:    gs.displaySpeed,
            lap:      gs.displayLap,
            lapTime:  gs.displayLapTime,
            isDrifting: gs.displayDrifting,
            carPos:   gs.carWorldPos,
            trackPath: gs.track
        )
    }

    /// Stops rendering, physics and every sound until the app is active again.
    @objc private func suspend() {
        resetInput()
        scnView?.isPlaying = false
        gameScene?.setActive(false)
    }

    @objc private func resume() {
        gameScene?.setActive(true)
        scnView?.isPlaying = true
    }

    private func resetInput() {
        controlsView?.reset()
        gameScene?.steerInput = 0
        gameScene?.throttleInput = 0
        gameScene?.brakeInput = 0
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .portrait }
    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
}
