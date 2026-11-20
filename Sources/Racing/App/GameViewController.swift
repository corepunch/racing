import UIKit
import SceneKit

/// One race: builds the circuit, runs it, shows the HUD, the pause panel and the results.
final class GameViewController: UIViewController {

    private let config: RaceConfig
    private var scnView: SCNView!
    private var gameScene: GameScene!
    private var hud: HUDView!
    private var controlsView: InputView!
    private var pauseButton: UIButton!
    private var panel: PanelView?
    private var hudTimer: Timer?
    private var loading: UIView?
    private var paused = false
    private let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private let soft = UIImpactFeedbackGenerator(style: .soft)
    private let rigid = UIImpactFeedbackGenerator(style: .rigid)

    /// Books the result (prize money, pink slips) and returns the lines for the results panel.
    var onFinish: ((RaceResult) -> [ResultLine])?
    /// Pays for another go; false hides RACE AGAIN (street challenges are one-off).
    var onRetry: (() -> Bool)?
    var retryTitle = "RACE AGAIN"
    /// Online: books the server's results and returns the payout lines.
    var onOnlineResults: (([NetResult]) -> [ResultLine])?
    /// Online: the player left the race from the pause panel.
    var onLeave: (() -> Void)?
    private var online: RaceClient? { config.online?.client }
    private var shownOnlineResults = false

    /// Debug flags passed on from the launch arguments.
    var autoDrive = false
    var debugDriver: GameScene.DebugDriver?

    init(config: RaceConfig) {
        self.config = config
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
        modalTransitionStyle = .crossDissolve
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UI.ink

        scnView = SCNView(frame: view.bounds)
        scnView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scnView.backgroundColor = UI.ink
        view.addSubview(scnView)

        let cover = UIView(frame: view.bounds)
        cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        cover.backgroundColor = UI.ink
        let name = UI.label(config.definition.name.uppercased(), UI.font(30, .black), .white, align: .center)
        let sub = UI.label("BUILDING CIRCUIT", UI.font(12, .bold), UI.cyan, align: .center)
        cover.addSubview(name)
        cover.addSubview(sub)
        NSLayoutConstraint.activate([
            name.centerXAnchor.constraint(equalTo: cover.centerXAnchor),
            name.centerYAnchor.constraint(equalTo: cover.centerYAnchor),
            name.widthAnchor.constraint(lessThanOrEqualTo: cover.widthAnchor, constant: -32),
            sub.centerXAnchor.constraint(equalTo: cover.centerXAnchor),
            sub.topAnchor.constraint(equalTo: name.bottomAnchor, constant: 10),
        ])
        UIView.animate(withDuration: 0.7, delay: 0, options: [.repeat, .autoreverse]) { sub.alpha = 0.25 }
        view.addSubview(cover)
        loading = cover

        let config = self.config
        let autoDrive = self.autoDrive, debugDriver = self.debugDriver
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let scene = GameScene(config: config)
            scene.autoDrive = autoDrive
            scene.debugDriver = debugDriver
            DispatchQueue.main.async { self?.installScene(scene) }
        }
    }

    private func installScene(_ scene: GameScene) {
        gameScene = scene
        scnView.scene     = scene.scene
        scnView.delegate  = scene
        scnView.pointOfView = scene.cameraNode
        scnView.isPlaying = true
        scnView.preferredFramesPerSecond = 60
        scnView.antialiasingMode         = .none
        scnView.rendersContinuously      = true

        controlsView = InputView(frame: view.bounds)
        controlsView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(controlsView)
        controlsView.becomeFirstResponder()

        hud = HUDView(frame: view.bounds)
        hud.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        hud.setTrack(scene.track)
        view.addSubview(hud)

        pauseButton = UIButton(type: .system)
        pauseButton.setImage(UIImage(systemName: "pause.fill"), for: .normal)
        pauseButton.tintColor = .white
        pauseButton.backgroundColor = UIColor(white: 0, alpha: 0.35)
        pauseButton.layer.cornerRadius = 20
        pauseButton.translatesAutoresizingMaskIntoConstraints = false
        pauseButton.addTarget(self, action: #selector(pauseTapped), for: .touchUpInside)
        view.addSubview(pauseButton)
        NSLayoutConstraint.activate([
            pauseButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            pauseButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            pauseButton.widthAnchor.constraint(equalToConstant: 40),
            pauseButton.heightAnchor.constraint(equalToConstant: 40),
        ])

        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(appInactive),
                           name: UIApplication.willResignActiveNotification, object: nil)
        center.addObserver(self, selector: #selector(appActive),
                           name: UIApplication.didBecomeActiveNotification, object: nil)
        if UIApplication.shared.applicationState != .active { appInactive() }

        hudTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.poll()
        }

        if let client = online {
            client.reportLoaded()
            if case .loading = client.phase { hud.announce("WAITING FOR THE OTHER DRIVERS", color: UI.cyan, hold: 4) }
        }

        if let cover = loading {
            view.bringSubviewToFront(cover)
            UIView.animate(withDuration: 0.35, animations: { cover.alpha = 0 }) { _ in cover.removeFromSuperview() }
            loading = nil
        }
    }

    // MARK: - Per-frame

    private func poll() {
        guard let gs = gameScene, !paused else { return }
        gs.steerInput = controlsView.steer
        gs.brakeInput = controlsView.brake
        gs.throttleInput = controlsView.throttle
        hud.update(gs.hud)
        for event in gs.drainEvents() { handle(event) }
        if let client = online, !shownOnlineResults, client.phase == .results, !client.results.isEmpty {
            shownOnlineResults = true
            showOnlineResults(client)
        }
    }

    private func handle(_ event: RaceEvent) {
        switch event {
        case .countdown(let n):
            if n > 0 {
                hud.flash("\(n)", color: .white)
                soft.impactOccurred()
            } else {
                hud.flash("GO", color: UI.cyan, hold: 0.9)
                heavy.impactOccurred()
                DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in self?.hud.setHintVisible(false) }
            }
        case .wallHit(let impact):
            rigid.impactOccurred(intensity: CGFloat(min(1, 0.35 + impact / 25)))
        case .boost:
            hud.announce("BOOST", color: UI.amber, hold: 0.9)
            soft.impactOccurred()
        case let .lap(time, best, lapsLeft):
            guard lapsLeft > 0 else { break }
            let text = (best ? "BEST LAP  " : "LAP  ") + UI.time(time)
            hud.announce(lapsLeft == 1 ? "FINAL LAP  ·  " + UI.time(time) : text, color: lapsLeft == 1 ? UI.magenta : UI.cyan,
                         hold: 2.2)
        case .finished(let result):
            if online != nil { showWaiting(result) } else { showResults(result) }
        }
    }

    // MARK: - Pause and results

    @objc private func pauseTapped() {
        guard panel == nil, gameScene != nil else { return }
        if online != nil {
            // The race goes on for everyone else; the car just coasts while the panel is up.
            controlsView.reset()
            let resume = GlowButton("RESUME", filled: true)
            resume.onTap = { [weak self] in self?.closePanel() }
            let leave = GlowButton("LEAVE RACE", tint: UI.magenta)
            leave.onTap = { [weak self] in self?.leaveOnline() }
            show(PanelView(title: "ONLINE", subtitle: "THE RACE KEEPS RUNNING", buttons: [resume, leave]))
            return
        }
        setPaused(true)
        let resume = GlowButton("RESUME", filled: true)
        resume.onTap = { [weak self] in self?.closePanel(); self?.setPaused(false) }
        let restart = GlowButton("RESTART")
        restart.onTap = { [weak self] in self?.restart() }
        let quit = GlowButton("QUIT TO MENU", tint: UI.magenta)
        quit.onTap = { [weak self] in self?.quit() }
        show(PanelView(title: "PAUSED", buttons: [resume, restart, quit]))
    }

    private func showResults(_ result: RaceResult) {
        heavy.impactOccurred()
        controlsView.reset()
        controlsView.isUserInteractionEnabled = false
        pauseButton.isHidden = true
        hud.setHintVisible(false)
        let winner = result.standings.first?.time
        let rows = result.standings.enumerated().map { i, s -> (left: String, right: String, highlight: Bool) in
            let right: String
            if let t = s.time {
                right = i == 0 || winner == nil ? UI.time(t) : String(format: "+%.2f", t - winner!)
            } else {
                right = "RACING"
            }
            return ("\(i + 1)  \(s.name)", right, s.isPlayer)
        }
        var subtitle = "TIME \(UI.time(result.time))  ·  BEST LAP \(UI.time(result.bestLap))"
        if result.isRecord { subtitle += "  ·  NEW RECORD" }
        let money = onFinish?(result) ?? []
        var buttons: [GlowButton] = []
        if onRetry != nil || onFinish == nil {
            let again = GlowButton(retryTitle, filled: true)
            again.onTap = { [weak self] in
                guard let self else { return }
                if let pay = self.onRetry, !pay() {
                    Toast.show("NOT ENOUGH CREDITS", in: self.view, color: UI.magenta)
                    return
                }
                self.restart()
            }
            buttons.append(again)
        }
        let menu = GlowButton("CONTINUE", filled: buttons.isEmpty)
        menu.onTap = { [weak self] in self?.quit() }
        buttons.append(menu)
        // Let the car cross the line on screen before the panel comes up.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self = self, self.panel == nil else { return }
            self.show(PanelView(title: UI.ordinal(result.position),
                                titleColor: result.position == 1 ? UI.amber : .white,
                                subtitle: subtitle, rows: rows, money: money, buttons: buttons))
        }
    }

    // MARK: - Online results

    /// Finished, but the order is the server's to call: show where things stand until it does.
    private func showWaiting(_ result: RaceResult) {
        heavy.impactOccurred()
        controlsView.reset()
        controlsView.isUserInteractionEnabled = false
        pauseButton.isHidden = true
        hud.setHintVisible(false)
        hud.flash("FINISHED", color: UI.cyan, hold: 1.6)
        hud.announce("TIME \(UI.time(result.time))  ·  WAITING FOR THE OTHERS", color: UI.cyan, hold: 30)
    }

    private func showOnlineResults(_ client: RaceClient) {
        let results = client.results
        let names = Dictionary(uniqueKeysWithValues: (config.online?.entries ?? []).map { ($0.id, $0.name) })
        let mine = config.online?.entries.first?.id
        let winner = results.first?.time
        let rows = results.enumerated().map { i, r -> (left: String, right: String, highlight: Bool) in
            let right: String
            if let t = r.time { right = i == 0 || winner == nil ? UI.time(t) : String(format: "+%.2f", t - winner!) }
            else { right = "DNF" }
            return ("\(i + 1)  \(names[r.carID] ?? "DRIVER")", right, r.carID == mine)
        }
        let position = (results.firstIndex { $0.carID == mine } ?? results.count) + 1
        let money = onOnlineResults?(results) ?? []
        let back = GlowButton("BACK TO LOBBY", filled: true)
        back.onTap = { [weak self] in
            if client.isHost { client.returnToLobby() }
            self?.quit()
        }
        closePanel()
        hud.announce("", hold: 0)
        show(PanelView(title: UI.ordinal(position), titleColor: position == 1 ? UI.amber : .white,
                       subtitle: client.settings.stake > 0 ? "BUY-IN \(Economy.credits(client.settings.stake))" : "FRIENDLY RACE",
                       rows: rows, money: money, buttons: [back]))
    }

    private func leaveOnline() {
        hudTimer?.invalidate()
        scnView.isPlaying = false
        let leave = onLeave
        dismiss(animated: true) { leave?() }
    }

    /// Called by the lobby when the connection drops mid-race.
    func connectionLost(_ reason: String) {
        guard isViewLoaded else { return }
        closePanel()
        let ok = GlowButton("OK", filled: true)
        ok.onTap = { [weak self] in self?.leaveOnline() }
        show(PanelView(title: "DISCONNECTED", subtitle: reason.uppercased(), buttons: [ok]))
    }

    private func show(_ newPanel: PanelView) {
        newPanel.frame = view.bounds
        newPanel.alpha = 0
        view.addSubview(newPanel)
        panel = newPanel
        UIView.animate(withDuration: 0.25) { newPanel.alpha = 1 }
    }

    private func closePanel() {
        panel?.removeFromSuperview()
        panel = nil
    }

    private func restart() {
        closePanel()
        controlsView.reset()
        controlsView.isUserInteractionEnabled = true
        pauseButton.isHidden = false
        hud.setHintVisible(true)
        gameScene.restart()
        setPaused(false)
    }

    private func quit() {
        hudTimer?.invalidate()
        scnView.isPlaying = false
        dismiss(animated: true)
    }

    private func setPaused(_ value: Bool) {
        paused = value
        if value { controlsView.reset() }
        gameScene?.steerInput = 0
        gameScene?.brakeInput = 0
        gameScene?.throttleInput = 1
        gameScene?.setActive(!value)
        scnView?.isPlaying = !value
    }

    @objc private func appInactive() {
        guard gameScene != nil, online == nil else { return }
        if panel == nil { pauseTapped() } else { setPaused(true) }
    }

    @objc private func appActive() {
        // Stays paused behind the panel until the player resumes; results keep running.
        if gameScene != nil, online == nil, pauseButton.isHidden { setPaused(false) }
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .portrait }
    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
}
