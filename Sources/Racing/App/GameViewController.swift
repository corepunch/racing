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

        // Launch arguments: `-track <0...3>` picks a circuit, `-autoDrive YES` runs the demo.
        let trackIndex = UserDefaults.standard.integer(forKey: "track")
        let definition = TrackLibrary.all[min(max(trackIndex, 0), TrackLibrary.all.count - 1)]
        let autoDrive = UserDefaults.standard.bool(forKey: "autoDrive")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let scene = GameScene(definition: definition)
            scene.autoDrive = autoDrive
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

        // ── On-screen controls ────────────────────────────────────────────────
        controlsView = InputView(frame: view.bounds)
        controlsView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        controlsView.onSteer    = { [weak self] v in self?.gameScene.steerInput    = v }
        controlsView.onThrottle = { [weak self] v in self?.gameScene.throttleInput = v }
        controlsView.onBrake    = { [weak self] v in self?.gameScene.brakeInput    = v }
        view.addSubview(controlsView)

        controlsView.becomeFirstResponder()

        // ── HUD polling timer ─────────────────────────────────────────────────
        hudTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.pollHUD()
        }
    }

    private func pollHUD() {
        guard let gs = gameScene, let hud = hudScene else { return }
        hud.updateHUD(
            speed:    gs.displaySpeed,
            lap:      gs.displayLap,
            lapTime:  gs.displayLapTime,
            surface:  gs.displaySurface,
            isDrifting: gs.displayDrifting,
            carPos:   gs.carWorldPos,
            trackPath: gs.track
        )
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscape }
    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
}
