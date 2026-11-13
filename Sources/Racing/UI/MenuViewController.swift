import UIKit
import SceneKit

/// The whole front end on one screen, laid out for one thumb: swipe the ship,
/// swipe the circuit, tap the two options, hit RACE.
final class MenuViewController: UIViewController {

    private let ships = ShipRoster.all
    private var tracks: [TrackDefinition] = []
    private var paths: [UInt64: TrackPath] = [:]

    private var shipIndex = 0
    private var trackIndex = 0
    private var assist = true
    private var difficulty = 1
    private var sectorSeed = 1977

    private let preview = SCNView()
    private let turntable = SCNNode()
    private var shipNode: SCNNode?

    private let shipName = UI.label("", UI.font(24, .black), .white)
    private let shipClass = UI.label("", UI.font(11, .bold), UI.cyan)
    private let shipCount = UI.label("", UI.digits(12, .semibold), UI.dim, align: .right)
    private var bars: [StatBar] = []

    private let trackCard = UIView()
    private let trackMap = TrackMapView()
    private let trackName = UI.label("", UI.font(19, .black), .white)
    private let trackInfo = UI.label("", UI.font(11, .bold), UI.dim)
    private let trackBest = UI.label("", UI.digits(12, .semibold), UI.dim)
    private let trackStripe = UIView()
    private let reroll = GlowButton("NEW SECTOR", tint: UI.amber, size: 10)

    private let assistButton = GlowButton("", size: 11)
    private let rivalsButton = GlowButton("", size: 11)
    private var didAutostart = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UI.ink
        let defaults = UserDefaults.standard
        defaults.register(defaults: ["menu.assist": true, "menu.difficulty": 1, "menu.sector": 1977])
        shipIndex = min(max(defaults.integer(forKey: "menu.ship"), 0), ships.count - 1)
        assist = defaults.bool(forKey: "menu.assist")
        difficulty = min(max(defaults.integer(forKey: "menu.difficulty"), 0), 2)
        sectorSeed = max(1, defaults.integer(forKey: "menu.sector"))
        tracks = TrackLibrary.all + [TrackLibrary.generated(seed: UInt64(sectorSeed))]
        trackIndex = min(max(defaults.integer(forKey: "menu.track"), 0), tracks.count - 1)

        buildPreview()
        buildLayout()
        showShip(animated: false)
        showTrack()
        showOptions()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        preview.isPlaying = true
        showTrack()   // best lap may have changed
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // `-autostart YES` goes straight into a race; `-track`, `-ship`, `-seed`, `-laps`, `-driver`, `-autoDrive` refine it.
        let defaults = UserDefaults.standard
        guard !didAutostart, defaults.bool(forKey: "autostart") else { return }
        didAutostart = true
        var definition = tracks[min(max(defaults.integer(forKey: "track"), 0), tracks.count - 1)]
        if defaults.integer(forKey: "seed") > 0 { definition = TrackLibrary.generated(seed: UInt64(defaults.integer(forKey: "seed"))) }
        var config = RaceConfig(definition: definition)
        config.shipIndex = defaults.integer(forKey: "ship")
        config.assist = assist
        config.difficulty = difficulty
        if defaults.integer(forKey: "laps") > 0 { config.laps = defaults.integer(forKey: "laps") }
        let game = GameViewController(config: config)
        game.autoDrive = defaults.bool(forKey: "autoDrive")
        game.debugDriver = defaults.string(forKey: "driver").flatMap(GameScene.DebugDriver.init(rawValue:))
        present(game, animated: false)
    }

    // MARK: - Ship preview

    private func buildPreview() {
        let scene = SCNScene()
        scene.background.contents = UI.ink
        let studio = ProceduralTextures.image(width: 64, height: 32) { _, v in
            // Bright band overhead, a cool glow at the horizon, dark below.
            let top = smoothstep(0.35, 0, v)
            let horizon = exp(-pow((v - 0.5) * 9, 2))
            return SIMD3(0.9, 0.95, 1) * top * 1.4 + SIMD3(0.1, 0.5, 0.9) * horizon * 0.8 + SIMD3(0.02, 0.02, 0.05)
        }
        scene.lightingEnvironment.contents = studio
        scene.lightingEnvironment.intensity = 1.0

        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .directional
        key.light?.intensity = 650
        key.eulerAngles = SCNVector3(-0.9, 0.6, 0)
        scene.rootNode.addChildNode(key)

        // Landing pad: a dark disc with two glowing rings.
        let pad = SCNNode(geometry: SCNCylinder(radius: 4.2, height: 0.08))
        pad.geometry?.firstMaterial?.lightingModel = .physicallyBased
        pad.geometry?.firstMaterial?.diffuse.contents = UIColor(red: 0.05, green: 0.06, blue: 0.1, alpha: 1)
        pad.geometry?.firstMaterial?.metalness.contents = 0.9
        pad.geometry?.firstMaterial?.roughness.contents = 0.35
        pad.position = SCNVector3(0, -0.9, 0)
        scene.rootNode.addChildNode(pad)
        for (radius, color) in [(CGFloat(4.0), UI.cyan), (CGFloat(2.6), UI.magenta)] {
            let ring = SCNNode(geometry: SCNTube(innerRadius: radius - 0.05, outerRadius: radius, height: 0.1))
            ring.geometry?.firstMaterial?.lightingModel = .constant
            ring.geometry?.firstMaterial?.diffuse.contents = UIColor.black
            ring.geometry?.firstMaterial?.emission.contents = color
            ring.position = SCNVector3(0, -0.84, 0)
            scene.rootNode.addChildNode(ring)
        }

        scene.rootNode.addChildNode(turntable)
        turntable.runAction(.repeatForever(.rotateBy(x: 0, y: -2 * .pi, z: 0, duration: 14)))

        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera?.fieldOfView = 38
        camera.position = SCNVector3(0, 3.0, 10.6)
        camera.simdLook(at: SIMD3(0, 0, 0))
        scene.rootNode.addChildNode(camera)

        preview.scene = scene
        preview.pointOfView = camera
        preview.backgroundColor = UI.ink
        preview.antialiasingMode = .multisampling4X
        preview.isPlaying = true
        preview.translatesAutoresizingMaskIntoConstraints = false
    }

    // MARK: - Layout

    private func buildLayout() {
        let safe = view.safeAreaLayoutGuide
        let title = UI.label("ARCLINE", UI.font(34, .black), .white, align: .center)
        let tag = UI.label("MAGLOCK LEAGUE  ·  SEASON 01", UI.font(10, .bold), UI.cyan, align: .center)

        // Ship block.
        let shipHead = UIStackView(arrangedSubviews: [shipName, shipCount])
        shipHead.alignment = .lastBaseline
        let shipBlock = UIStackView(arrangedSubviews: [shipClass, shipHead])
        shipBlock.axis = .vertical
        shipBlock.spacing = 1
        bars = ShipSpec.statNames.map { StatBar(name: $0) }
        let statGrid = UIStackView(arrangedSubviews: bars)
        statGrid.axis = .vertical
        statGrid.spacing = 7

        // Track card.
        trackCard.backgroundColor = UI.panel
        trackCard.layer.cornerRadius = 12
        trackCard.layer.borderWidth = 1
        trackCard.layer.borderColor = UIColor(white: 1, alpha: 0.12).cgColor
        trackCard.translatesAutoresizingMaskIntoConstraints = false
        trackStripe.translatesAutoresizingMaskIntoConstraints = false
        trackStripe.layer.cornerRadius = 2
        let trackText = UIStackView(arrangedSubviews: [UI.label("CIRCUIT", UI.font(10, .bold), UI.cyan), trackName, trackInfo, trackBest])
        trackText.axis = .vertical
        trackText.spacing = 3
        trackText.translatesAutoresizingMaskIntoConstraints = false
        let previous = arrow("chevron.left") { [weak self] in self?.stepTrack(-1) }
        let next = arrow("chevron.right") { [weak self] in self?.stepTrack(1) }
        reroll.onTap = { [weak self] in self?.rerollSector() }
        [trackStripe, trackMap, trackText, previous, next, reroll].forEach(trackCard.addSubview)

        // Options and the go button.
        assistButton.onTap = { [weak self] in self?.toggleAssist() }
        rivalsButton.onTap = { [weak self] in self?.cycleRivals() }
        let options = UIStackView(arrangedSubviews: [assistButton, rivalsButton])
        options.spacing = 10
        options.distribution = .fillEqually
        let race = GlowButton("RACE", filled: true, size: 24)
        race.onTap = { [weak self] in self?.startRace() }

        let lower = UIStackView(arrangedSubviews: [shipBlock, statGrid, trackCard, options, race])
        lower.axis = .vertical
        lower.spacing = 12
        lower.setCustomSpacing(8, after: shipBlock)
        lower.setCustomSpacing(16, after: statGrid)
        lower.translatesAutoresizingMaskIntoConstraints = false

        let shipPrev = arrow("chevron.left") { [weak self] in self?.stepShip(-1) }
        let shipNext = arrow("chevron.right") { [weak self] in self?.stepShip(1) }

        [preview, title, tag, lower, shipPrev, shipNext].forEach(view.addSubview)
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: safe.topAnchor, constant: 4),
            title.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            tag.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 0),
            tag.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            lower.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 20),
            lower.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -20),
            lower.bottomAnchor.constraint(equalTo: safe.bottomAnchor, constant: -10),

            preview.topAnchor.constraint(equalTo: tag.bottomAnchor, constant: 0),
            preview.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            preview.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            preview.bottomAnchor.constraint(equalTo: lower.topAnchor, constant: -4),

            shipPrev.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 6),
            shipPrev.centerYAnchor.constraint(equalTo: preview.centerYAnchor, constant: 30),
            shipNext.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -6),
            shipNext.centerYAnchor.constraint(equalTo: shipPrev.centerYAnchor),

            trackCard.heightAnchor.constraint(equalToConstant: 118),
            trackStripe.leadingAnchor.constraint(equalTo: trackCard.leadingAnchor, constant: 44),
            trackStripe.topAnchor.constraint(equalTo: trackCard.topAnchor, constant: 14),
            trackStripe.bottomAnchor.constraint(equalTo: trackCard.bottomAnchor, constant: -14),
            trackStripe.widthAnchor.constraint(equalToConstant: 4),
            trackMap.leadingAnchor.constraint(equalTo: trackStripe.trailingAnchor, constant: 6),
            trackMap.centerYAnchor.constraint(equalTo: trackCard.centerYAnchor),
            trackMap.widthAnchor.constraint(equalToConstant: 96),
            trackMap.heightAnchor.constraint(equalToConstant: 96),
            trackText.leadingAnchor.constraint(equalTo: trackMap.trailingAnchor, constant: 10),
            trackText.trailingAnchor.constraint(equalTo: next.leadingAnchor, constant: -2),
            trackText.centerYAnchor.constraint(equalTo: trackCard.centerYAnchor),
            previous.leadingAnchor.constraint(equalTo: trackCard.leadingAnchor),
            previous.centerYAnchor.constraint(equalTo: trackCard.centerYAnchor),
            next.trailingAnchor.constraint(equalTo: trackCard.trailingAnchor),
            next.centerYAnchor.constraint(equalTo: trackCard.centerYAnchor),
            reroll.trailingAnchor.constraint(equalTo: next.leadingAnchor, constant: 0),
            reroll.bottomAnchor.constraint(equalTo: trackCard.bottomAnchor, constant: -10),
            reroll.widthAnchor.constraint(equalToConstant: 104),
            reroll.heightAnchor.constraint(equalToConstant: 30),

            options.heightAnchor.constraint(equalToConstant: 44),
            race.heightAnchor.constraint(equalToConstant: 66),
        ])

        // Swipes anywhere on the ship or the card change the selection.
        for (target, action) in [(preview as UIView, #selector(swipeShip(_:))), (trackCard, #selector(swipeTrack(_:)))] {
            for direction in [UISwipeGestureRecognizer.Direction.left, .right] {
                let swipe = UISwipeGestureRecognizer(target: self, action: action)
                swipe.direction = direction
                target.addGestureRecognizer(swipe)
            }
        }
    }

    private func arrow(_ symbol: String, _ action: @escaping () -> Void) -> UIButton {
        let button = UIButton(type: .system, primaryAction: UIAction { _ in
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        })
        let image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .heavy))
        button.setImage(image, for: .normal)
        button.tintColor = UIColor(white: 1, alpha: 0.8)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 44).isActive = true
        button.heightAnchor.constraint(equalToConstant: 64).isActive = true
        return button
    }

    // MARK: - Selection

    @objc private func swipeShip(_ swipe: UISwipeGestureRecognizer) { stepShip(swipe.direction == .left ? 1 : -1) }
    @objc private func swipeTrack(_ swipe: UISwipeGestureRecognizer) { stepTrack(swipe.direction == .left ? 1 : -1) }

    private func stepShip(_ delta: Int) {
        shipIndex = (shipIndex + delta + ships.count) % ships.count
        UserDefaults.standard.set(shipIndex, forKey: "menu.ship")
        showShip(animated: true)
    }

    private func stepTrack(_ delta: Int) {
        trackIndex = (trackIndex + delta + tracks.count) % tracks.count
        UserDefaults.standard.set(trackIndex, forKey: "menu.track")
        showTrack()
    }

    private func rerollSector() {
        sectorSeed = Int.random(in: 100...9999)
        UserDefaults.standard.set(sectorSeed, forKey: "menu.sector")
        tracks[tracks.count - 1] = TrackLibrary.generated(seed: UInt64(sectorSeed))
        showTrack()
    }

    private func toggleAssist() {
        assist.toggle()
        UserDefaults.standard.set(assist, forKey: "menu.assist")
        showOptions()
    }

    private func cycleRivals() {
        difficulty = (difficulty + 1) % 3
        UserDefaults.standard.set(difficulty, forKey: "menu.difficulty")
        showOptions()
    }

    private func showShip(animated: Bool) {
        let design = ships[shipIndex]
        shipNode?.removeFromParentNode()
        let node = ShipMesh.build(design)
        ShipMesh.setThrust(0.3, on: node)
        node.eulerAngles = SCNVector3(0, 0.6, 0)
        turntable.addChildNode(node)
        shipNode = node
        if animated {
            node.opacity = 0
            node.position = SCNVector3(0, 0.8, 0)
            node.runAction(.group([.fadeIn(duration: 0.2), .move(to: SCNVector3Zero, duration: 0.25)]))
        }
        shipName.text = design.name
        shipClass.text = design.className
        shipClass.textColor = UI.color(design.glow)
        shipCount.text = "\(shipIndex + 1) / \(ships.count)"
        for (bar, value) in zip(bars, design.spec.ratings) { bar.set(value, color: UI.color(design.primary), animated: animated) }
    }

    private func showTrack() {
        guard !tracks.isEmpty else { return }
        let definition = tracks[trackIndex]
        let path = paths[definition.seed] ?? TrackPath(definition: definition, spacing: 8)
        paths[definition.seed] = path
        let neon = UI.color(definition.theme.neonA)
        trackName.text = definition.name.uppercased()
        trackInfo.text = String(format: "%.1f KM  ·  3 LAPS  ·  %d / %d", path.totalLength / 1000, trackIndex + 1, tracks.count)
        trackBest.text = "BEST LAP  " + UI.time(Records.bestLap(for: definition))
        trackStripe.backgroundColor = neon
        trackMap.lineColor = neon
        trackMap.setTrack(path, every: 2)
        reroll.isHidden = trackIndex != tracks.count - 1
    }

    private func showOptions() {
        assistButton.setTitleText("WALL GUARD  " + (assist ? "ON" : "OFF"))
        assistButton.alpha = assist ? 1 : 0.6
        rivalsButton.setTitleText("RIVALS  " + ["EASY", "NORMAL", "HARD"][difficulty])
    }

    private func startRace() {
        var config = RaceConfig(definition: tracks[trackIndex])
        config.shipIndex = shipIndex
        config.assist = assist
        config.difficulty = difficulty
        preview.isPlaying = false
        present(GameViewController(config: config), animated: true)
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .portrait }
    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
}

/// One labelled stat bar.
private final class StatBar: UIView {
    private let fill = UIView()
    private var width: NSLayoutConstraint!
    private let track = UIView()

    init(name: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let label = UI.label(name, UI.font(10, .bold), UI.dim)
        track.backgroundColor = UIColor(white: 1, alpha: 0.1)
        track.layer.cornerRadius = 3
        track.translatesAutoresizingMaskIntoConstraints = false
        fill.layer.cornerRadius = 3
        fill.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        addSubview(track)
        track.addSubview(fill)
        width = fill.widthAnchor.constraint(equalTo: track.widthAnchor, multiplier: 0.5)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 12),
            label.leadingAnchor.constraint(equalTo: leadingAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.widthAnchor.constraint(equalToConstant: 74),
            track.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 8),
            track.trailingAnchor.constraint(equalTo: trailingAnchor),
            track.centerYAnchor.constraint(equalTo: centerYAnchor),
            track.heightAnchor.constraint(equalToConstant: 6),
            fill.leadingAnchor.constraint(equalTo: track.leadingAnchor),
            fill.topAnchor.constraint(equalTo: track.topAnchor),
            fill.bottomAnchor.constraint(equalTo: track.bottomAnchor),
            width,
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func set(_ value: Float, color: UIColor, animated: Bool) {
        width.isActive = false
        width = fill.widthAnchor.constraint(equalTo: track.widthAnchor, multiplier: CGFloat(max(0.04, min(1, value))))
        width.isActive = true
        fill.backgroundColor = color
        if animated { UIView.animate(withDuration: 0.25) { self.layoutIfNeeded() } }
    }
}
