import SceneKit
import simd

struct RaceConfig {
    var definition: TrackDefinition
    var shipIndex = 0
    var laps = 3
    /// The wall-guard pilot assist (see `Ship.guardYaw`).
    var assist = true
    /// 0 easy, 1 normal, 2 hard.
    var difficulty = 1
}

struct RaceStanding {
    var name: String
    var color: SIMD3<Float>
    var isPlayer: Bool
    /// Finish time, or nil if still racing when the player finished.
    var time: Float?
}

struct RaceResult {
    var position: Int
    var time: Float
    var bestLap: Float?
    var isRecord: Bool
    var standings: [RaceStanding]
}

enum RaceEvent {
    /// 3, 2, 1, then 0 for GO.
    case countdown(Int)
    case wallHit(Float)
    case boost
    case lap(time: Float, best: Bool, lapsLeft: Int)
    case finished(RaceResult)
}

/// What the HUD shows, copied out once a frame.
struct HUDState {
    var speedKMH: Float = 0
    var lap = 1
    var laps = 3
    var position = 1
    var count = 1
    var raceTime: Float = 0
    var lapTime: Float = 0
    var bestLap: Float?
    var boosting = false
    var racing = false
    /// Minimap dots in 0...1, player last.
    var dots: [(position: SIMD2<Float>, color: SIMD3<Float>, isPlayer: Bool)] = []
}

/// Best laps per circuit, kept in user defaults.
enum Records {
    static func bestLap(for definition: TrackDefinition) -> Float? {
        let value = UserDefaults.standard.float(forKey: "bestLap.\(definition.seed)")
        return value > 0 ? value : nil
    }

    static func setBestLap(_ time: Float, for definition: TrackDefinition) {
        UserDefaults.standard.set(time, forKey: "bestLap.\(definition.seed)")
    }
}

/// Owns the scene, the ships, the camera and the race itself. The per-frame loop
/// runs from SceneKit's render callback.
final class GameScene: NSObject, SCNSceneRendererDelegate {

    let scene = SCNScene()
    let track: TrackPath
    let config: RaceConfig

    private(set) var ships: [Ship] = []
    private var player: Ship { ships[0] }
    private var lapsDone: [Int] = []
    private var laneTimers: [Float] = []
    private var boostSections: [Bool] = []
    private var rng = SplitMix64(seed: 4242)

    private(set) var cameraNode: SCNNode!
    private var camera: SCNCamera!
    private var cameraForward: SIMD3<Float>?
    private var cameraFOV: Float = 70

    // --- Inputs (set by GameViewController) ---
    var steerInput: Float = 0
    var brakeInput: Float = 0

    /// Demo: every ship is flown by the rival driver, no countdown, no finish.
    var autoDrive = false { didSet { if autoDrive { phase = .racing } } }
    /// Debug stand-ins for the player, with telemetry printed every two seconds (`-driver <name>`).
    enum DebugDriver: String {
        /// The rival driver flies the player's ship.
        case rival
        /// Nobody touches the screen: shows what the ship and the assist do on their own.
        case handsOff = "handsoff"
        /// A casual thumb: steers a quarter of a second late and never brakes.
        case casual
    }
    var debugDriver: DebugDriver?
    private var steerHistory: [Float] = []
    private var telemetryTime: Float = 0
    private var telemetryHits = 0
    private var telemetryScrape: Float = 0

    private enum Phase { case countdown(Float), racing, finished }
    private var phase = Phase.countdown(3.6)
    private var raceTime: Float = 0
    private var lastTime: TimeInterval?

    // --- Shared with the main thread ---
    private let lock = NSLock()
    private var hudState = HUDState()
    private var events: [RaceEvent] = []

    var hud: HUDState {
        lock.lock(); defer { lock.unlock() }
        return hudState
    }

    /// Hands over everything that happened since the last call.
    func drainEvents() -> [RaceEvent] {
        lock.lock(); defer { lock.unlock() }
        let out = events
        events.removeAll()
        return out
    }

    private func emit(_ event: RaceEvent) {
        lock.lock(); events.append(event); lock.unlock()
    }

    // MARK: - Init

    init(config: RaceConfig) {
        self.config = config
        track = TrackPath(definition: config.definition)
        super.init()
        buildScene()
        restart()
    }

    /// Used by the track recorder.
    convenience init(definition: TrackDefinition = TrackLibrary.all[0], audio: Bool = true) {
        self.init(config: RaceConfig(definition: definition))
    }

    private func buildScene() {
        let theme = track.definition.theme
        let sky = ProceduralTextures.sky(theme: theme, seed: track.definition.seed)
        scene.background.contents = sky
        scene.lightingEnvironment.contents = sky
        scene.lightingEnvironment.intensity = theme.environment
        scene.fogStartDistance = theme.fogStart
        scene.fogEndDistance = theme.fogEnd
        scene.fogDensityExponent = 1.4
        scene.fogColor = Self.color(theme.skyHorizon)

        addLighting(theme)

        // Everything below is generated from the track's master curve.
        scene.rootNode.addChildNode(TrackMeshBuilder.buildTrackNode(path: track))
        scene.rootNode.addChildNode(CityScenery.build(path: track))
        boostSections = TrackSections.plan(path: track).map { $0.deck == .boost }

        // The player's ship first, then every other design as a rival.
        let roster = ShipRoster.all
        let chosen = min(max(config.shipIndex, 0), roster.count - 1)
        let order = [chosen] + roster.indices.filter { $0 != chosen }
        ships = order.map { Ship(design: roster[$0]) }
        ships.forEach { scene.rootNode.addChildNode($0.node) }

        setupCamera()
    }

    /// Puts everyone back on the grid and starts the countdown.
    func restart() {
        lock.lock(); events.removeAll(); lock.unlock()
        let count = ships.count
        let lanes: [Float] = [-4.5, 4.5, -1.6, 1.6, 0, -3]
        let basePace: Float = [0.9, 0.95, 1.0][min(max(config.difficulty, 0), 2)]
        for (i, ship) in ships.enumerated() {
            // Rivals fill the front of the grid; the player starts at the back.
            let slot = i == 0 ? count - 1 : i - 1
            ship.place(progress: -(10 + 7 * Float(slot)), lateral: slot % 2 == 0 ? -3.2 : 3.2, on: track)
            ship.lane = i == 0 ? 0 : lanes[(i - 1) % lanes.count]
            ship.pace = i == 0 ? 1 : basePace - 0.012 * Float(i - 1)
        }
        lapsDone = Array(repeating: 0, count: count)
        laneTimers = (0..<count).map { 3 + Float($0) * 1.7 }
        raceTime = 0
        steerHistory.removeAll()
        cameraForward = nil
        phase = autoDrive ? .racing : .countdown(3.6)
        publishHUD()
    }

    private static func color(_ c: SIMD3<Float>) -> UIColor {
        UIColor(red: CGFloat(c.x), green: CGFloat(c.y), blue: CGFloat(c.z), alpha: 1)
    }

    private func addLighting(_ theme: TrackTheme) {
        let sunLight         = SCNLight()
        sunLight.type        = .directional
        sunLight.color       = Self.color(theme.sunColor)
        sunLight.intensity   = theme.sunIntensity
        sunLight.castsShadow = true
        sunLight.shadowMode  = .forward
        sunLight.shadowSampleCount = 1
        sunLight.shadowRadius = 0
        sunLight.shadowMapSize = CGSize(width: 2048, height: 2048)
        sunLight.shadowCascadeCount = 4
        sunLight.shadowCascadeSplittingFactor = 0.8
        sunLight.automaticallyAdjustsShadowProjection = true
        sunLight.maximumShadowDistance = 200
        sunLight.shadowColor = UIColor(white: 0, alpha: 0.5)
        let sunNode          = SCNNode()
        sunNode.light        = sunLight
        sunNode.eulerAngles  = SCNVector3(theme.sunAngles.x, theme.sunAngles.y, 0)
        scene.rootNode.addChildNode(sunNode)

        let ambLight         = SCNLight()
        ambLight.type        = .ambient
        ambLight.color       = Self.color(simd_mix(theme.skyHorizon, SIMD3(repeating: 1), SIMD3(repeating: 0.4)))
        ambLight.intensity   = theme.ambient
        let ambNode          = SCNNode()
        ambNode.light        = ambLight
        scene.rootNode.addChildNode(ambNode)
    }

    /// Freezes the game while the app is inactive or the race is paused.
    func setActive(_ active: Bool) {
        scene.isPaused = !active
        lastTime = nil
    }

    private func setupCamera() {
        camera               = SCNCamera()
        camera.fieldOfView   = 70
        camera.zFar          = 2400
        camera.zNear         = 0.5
        // HDR is only on for the bloom around the generated emissive markings.
        camera.wantsHDR = true
        camera.wantsExposureAdaptation = false
        camera.motionBlurIntensity = 0
        camera.bloomIntensity = 0.45
        camera.bloomThreshold = 1.0
        camera.bloomBlurRadius = 10

        cameraNode           = SCNNode()
        cameraNode.camera    = camera
        scene.rootNode.addChildNode(cameraNode)
    }

    // MARK: - Frame update (SCNSceneRendererDelegate)

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        guard let last = lastTime else {
            lastTime = time
            updateCamera(dt: 0)
            return
        }
        let dt = min(Float(time - last), 1.0 / 30.0)
        lastTime = time
        guard dt > 0 else { return }

        switch phase {
        case .countdown(let left):
            let now = left - dt
            for ship in ships { ship.step(dt: dt, input: ShipInput(), track: track, throttle: 0) }
            if Int(ceil(now)) != Int(ceil(left)), now > 0, now <= 3 { emit(.countdown(Int(ceil(now)))) }
            if now <= 0 {
                phase = .racing
                emit(.countdown(0))
            } else {
                phase = .countdown(now)
            }
        case .racing, .finished:
            raceTime += dt
            stepShips(dt: dt)
        }

        updateCamera(dt: dt)
        publishHUD()
        if debugDriver != nil { printTelemetry(dt: dt) }
    }

    // MARK: - Race

    private func stepShips(dt: Float) {
        let length = track.totalLength
        let playerFinished = player.finishTime != nil

        for (i, ship) in ships.enumerated() {
            let human = i == 0 && !autoDrive && debugDriver != .rival && !playerFinished
            if human {
                var input = ShipInput(steer: steerInput, brake: brakeInput)
                if debugDriver == .handsOff { input = ShipInput() }
                if debugDriver == .casual {
                    steerHistory.append(RivalDriver.input(for: ship, track: track).steer)
                    if steerHistory.count > 15 { steerHistory.removeFirst() }
                    input = ShipInput(steer: steerHistory[0], brake: 0)
                }
                ship.step(dt: dt, input: input, track: track,
                          wallGuard: config.assist ? 1 : 0)
            } else {
                updateRival(i, dt: dt)
                // A finished ship cruises its lap of honour.
                let throttle: Float = ship.finishTime != nil ? 0.6 : 1
                ship.step(dt: dt, input: RivalDriver.input(for: ship, track: track), track: track, throttle: throttle)
            }

            // Boost pads cover the middle of the deck.
            let section = Int(ship.s / track.step) / TrackPath.sectionSamples
            if boostSections[section % boostSections.count], abs(ship.d) < 0.44 * track.frame(at: ship.s).halfWidth {
                ship.giveBoost()
            }

            if i == 0 {
                if ship.pendingHit > 0 { emit(.wallHit(ship.pendingHit)); spark(at: ship); telemetryHits += 1 }
                if ship.pendingBoost { emit(.boost) }
                if ship.scraping { telemetryScrape += dt }
            }
            ship.pendingHit = 0
            ship.pendingBoost = false

            // Laps.
            let done = Int((ship.progress / length).rounded(.down))
            if done > lapsDone[i], ship.finishTime == nil {
                lapsDone[i] = done
                let lapTime = raceTime - ship.lapStart
                ship.lapStart = raceTime
                ship.lastLap = lapTime
                let best = ship.bestLap.map { lapTime < $0 } ?? true
                if best { ship.bestLap = lapTime }
                if !autoDrive, done >= config.laps { ship.finishTime = raceTime }
                if i == 0, !autoDrive {
                    emit(.lap(time: lapTime, best: best, lapsLeft: config.laps - done))
                    if ship.finishTime != nil { finishRace() }
                }
            }
        }
        collideShips()
    }

    /// Lane choice, traffic and a little rubber band for rival `i`.
    private func updateRival(_ i: Int, dt: Float) {
        let ship = ships[i]
        let length = track.totalLength
        laneTimers[i] -= dt
        if laneTimers[i] <= 0 {
            laneTimers[i] = rng.float(4...9)
            ship.lane = rng.float(-5...5)
        }
        // Pull out from behind a slower ship.
        var wanted: Float = 0
        for other in ships where other !== ship {
            var gap = other.s - ship.s
            if gap < -length / 2 { gap += length }
            if gap > 0, gap < 28, abs(other.d - ship.d) < 3, other.speed < ship.speed + 2 {
                wanted = other.d > ship.d ? -3.6 : 3.6
            }
        }
        ship.avoid += (wanted - ship.avoid) * min(1, 2.5 * dt)

        guard i != 0, !autoDrive else { return }
        // Rubber band: rivals far ahead ease off a little, rivals far behind push.
        let basePace: Float = [0.9, 0.95, 1.0][min(max(config.difficulty, 0), 2)] - 0.012 * Float(i - 1)
        let lead = ship.progress - player.progress
        let band = max(-0.035, min(0.035, -lead / 4000))
        ship.pace += (basePace + band - ship.pace) * min(1, dt)
    }

    /// Ships shoulder each other apart; running into the back of one costs the speed difference.
    private func collideShips() {
        let length = track.totalLength
        for a in 0..<ships.count {
            for b in (a + 1)..<ships.count {
                let first = ships[a], second = ships[b]
                var along = first.s - second.s
                if along > length / 2 { along -= length }
                if along < -length / 2 { along += length }
                let across = first.d - second.d
                guard abs(along) < 4.8, abs(across) < 3.2 else { continue }
                let push = (3.2 - abs(across)) / 2 * (across >= 0 ? 1 : -1)
                let front = along > 0 ? first : second, rear = along > 0 ? second : first
                var rearScale: Float = 0.995
                if abs(along) > 2.4, rear.speed > front.speed {
                    rearScale = max(0.9, front.speed / rear.speed)
                }
                first.nudge(lateral: push, speedScale: first === rear ? rearScale : 1)
                second.nudge(lateral: -push, speedScale: second === rear ? rearScale : 1)
            }
        }
    }

    /// Finishers by time, then everyone else by distance covered.
    private func ranking() -> [Ship] {
        ships.sorted { a, b in
            switch (a.finishTime, b.finishTime) {
            case let (x?, y?): return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.progress > b.progress
            }
        }
    }

    private func finishRace() {
        phase = .finished
        let order = ranking()
        let position = (order.firstIndex { $0 === player } ?? 0) + 1
        var record = false
        if debugDriver == nil, let best = player.bestLap {
            let previous = Records.bestLap(for: config.definition)
            if previous.map({ best < $0 }) ?? true {
                Records.setBestLap(best, for: config.definition)
                record = true
            }
        }
        let standings = order.map {
            RaceStanding(name: $0.design.name, color: $0.design.primary, isPlayer: $0 === player, time: $0.finishTime)
        }
        emit(.finished(RaceResult(position: position, time: raceTime, bestLap: player.bestLap,
                                  isRecord: record, standings: standings)))
    }

    private func publishHUD() {
        var state = HUDState()
        let order = ranking()
        state.speedKMH = player.speed * 3.6
        state.laps = config.laps
        state.lap = min(config.laps, max(1, lapsDone.first.map { $0 + 1 } ?? 1))
        state.position = (order.firstIndex { $0 === player } ?? 0) + 1
        state.count = ships.count
        state.raceTime = player.finishTime ?? raceTime
        state.lapTime = raceTime - player.lapStart
        state.bestLap = player.bestLap
        state.boosting = player.boost > 0
        if case .racing = phase { state.racing = true }
        state.dots = ships.reversed().map {
            (track.minimapPosition(for: $0.worldPosition), $0.design.primary, $0 === player)
        }
        lock.lock(); hudState = state; lock.unlock()
    }

    // MARK: - Effects

    private static let sparkImage: UIImage = {
        UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { ctx in
            UIColor.white.setFill()
            ctx.cgContext.fillEllipse(in: CGRect(x: 0, y: 0, width: 8, height: 8))
        }
    }()

    private func spark(at ship: Ship) {
        let system = SCNParticleSystem()
        system.particleImage = Self.sparkImage
        system.birthRate = 220
        system.emissionDuration = 0.08
        system.loops = false
        system.particleLifeSpan = 0.3
        system.particleVelocity = 9
        system.particleVelocityVariation = 8
        system.spreadingAngle = 70
        system.particleSize = 0.03
        system.particleSizeVariation = 0.015
        system.particleColor = UIColor(red: 1, green: 0.7, blue: 0.25, alpha: 1)
        system.blendMode = .additive
        system.isAffectedByGravity = true
        system.isLightingEnabled = false
        let frame = track.frame(at: ship.s)
        let emitter = SCNNode()
        emitter.simdPosition = ship.worldPosition + frame.right * (ship.d > 0 ? 1.2 : -1.2)
        emitter.addParticleSystem(system)
        scene.rootNode.addChildNode(emitter)
        emitter.runAction(.sequence([.wait(duration: 1), .removeFromParentNode()]))
    }

    // MARK: - Camera

    private func updateCamera(dt: Float) {
        let ship = player
        let frame = track.frame(at: ship.s)
        // Follow the direction of travel, so a slide shows the ship turned across the view.
        var forward = cameraForward ?? ship.worldForward
        forward = simd_normalize(forward + (ship.worldForward - forward) * min(1, 6.5 * dt))
        cameraForward = forward
        // Lean with the banking, but not all the way.
        let up = simd_normalize(simd_mix(SIMD3<Float>(0, 1, 0), frame.up, SIMD3(repeating: 0.65)))

        let boosting: Float = ship.boost > 0 ? 1 : 0
        let behind: Float = 13
        let above: Float = 5.2
        // Mostly level, so a climb does not drop the camera on to the deck.
        let level = simd_normalize(SIMD3<Float>(forward.x, forward.y * 0.4, forward.z))
        var position = ship.worldPosition - level * behind + up * above
        // Never dip under the deck behind a crest.
        let back = track.frame(at: ship.s - behind)
        position.y = max(position.y, back.position.y + 1.6)
        cameraNode.simdPosition = position
        cameraNode.simdLook(at: ship.worldPosition + forward * 16 + up * 0.6, up: up, localFront: SIMD3<Float>(0, 0, -1))

        let fov = 66 + min(ship.speed, 120) * 0.15 + boosting * 7
        cameraFOV += (fov - cameraFOV) * (dt > 0 ? min(1, 4 * dt) : 1)
        camera.fieldOfView = CGFloat(cameraFOV)
    }

    // MARK: - Telemetry (debug)

    private func printTelemetry(dt: Float) {
        telemetryTime += dt
        guard telemetryTime > 2 else { return }
        telemetryTime = 0
        let order = ranking()
        let line = order.map { ship -> String in
            String(format: "%@%@ %.0fm %.0fkm/h", ship === player ? "*" : "", ship.design.name, ship.progress, ship.speed * 3.6)
        }.joined(separator: " | ")
        print(String(format: "[race] t=%.0fs P%d %.0fm %.0fkm/h lap=%d last=%.1fs hits=%d scrape=%.0fs pads=%d len=%.0fm :: %@",
                     raceTime, (order.firstIndex { $0 === player } ?? 0) + 1, player.progress, player.speed * 3.6,
                     lapsDone[0] + 1, player.lastLap ?? 0, telemetryHits, telemetryScrape,
                     boostSections.filter { $0 }.count, track.totalLength, line))
    }
}
