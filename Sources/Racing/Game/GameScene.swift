import SceneKit
import SpriteKit
import simd
import AVFoundation

/// Main game orchestrator.  Owns the SCNScene, track, car controller, camera,
/// lap timing, and the per-frame physics loop via SCNSceneRendererDelegate.
final class GameScene: NSObject, SCNSceneRendererDelegate {

    let scene = SCNScene()

    // --- Sub-systems ---
    let track: TrackPath
    private let physics   = CarController()
    private var carNode: CarNode!
    private let audioEnabled: Bool

    // --- Car style (change to any CarStyle case to swap the visual model) ---
    var carStyle: CarStyle = .truckGreen

    // --- Audio ---
    private var enginePlayer: AVAudioPlayer?
    private var skidPlayer:   AVAudioPlayer?
    private(set) var cameraNode: SCNNode!
    private var camera: SCNCamera!

    // --- Inputs (set by GameViewController / InputManager) ---
    var throttleInput: Float = 0
    var brakeInput: Float    = 0
    var steerInput: Float    = 0

    // --- Demo auto-drive ---
    var autoDrive = false { didSet { physics.setDemo(autoDrive) } }
    private var autoDriveProgress: Float = 0
    private var autoDriveSpeed: Float = 30

    /// Debug driver: steers and brakes the real physics car round the lap (`-selfDrive YES`).
    var selfDrive = false
    private var flippedTime: Float = 0
    private var telemetryTime: TimeInterval = 0
    private var telemetryTop: Float = 0

    // --- Lap state ---
    private var lapCount       = 0
    private var lapStartTime: TimeInterval = 0
    private var lastLapTime: TimeInterval  = 0
    private var sessionTime: TimeInterval  = 0
    private var firstFrame     = true
    private var prevSampleIdx  = 0

    // HUD read-outs (GameViewController polls these)
    private(set) var displaySpeed: Float    = 0
    private(set) var displayLap: Int        = 0
    private(set) var displayLapTime: TimeInterval = 0
    private(set) var displayDrifting        = false
    private(set) var carWorldPos: SIMD3<Float> = .zero

    // MARK: - Init

    init(definition: TrackDefinition = TrackLibrary.all[0], audio: Bool = true) {
        track = TrackPath(definition: definition)
        audioEnabled = audio
        super.init()
        buildScene()
    }

    // MARK: - Scene setup

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

        // Car
        carNode = CarNode(style: carStyle)
        let startSample = track.samples[0]
        scene.rootNode.addChildNode(carNode)
        physics.install(on: carNode, in: scene.physicsWorld, at: startSample)

        // Camera
        setupCamera()

        // Audio
        if audioEnabled { setupAudio() }
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

    private func setupAudio() {
        func makePlayer(_ name: String, loops: Bool) -> AVAudioPlayer? {
            guard let url = Bundle.main.url(forResource: name, withExtension: "m4a",
                                            subdirectory: "Audio") else { return nil }
            let p = try? AVAudioPlayer(contentsOf: url)
            p?.numberOfLoops = loops ? -1 : 0
            p?.prepareToPlay()
            return p
        }
        enginePlayer = makePlayer("engine", loops: true)
        enginePlayer?.enableRate = true
        enginePlayer?.volume = 0
        enginePlayer?.play()
        skidPlayer = makePlayer("skid", loops: true)
        skidPlayer?.volume = 0
        skidPlayer?.play()
    }

    private func updateAudio() {
        let spd = physics.speedKMH
        // Engine pitch: idle at 0.6, max at ~1.4 around 160 km/h
        let targetVol: Float = min(spd / 60.0, 1.0)
        let curVol = enginePlayer?.volume ?? 0
        enginePlayer?.volume = curVol + (targetVol - curVol) * 0.08
        enginePlayer?.rate   = min(2, 0.6 + Float(spd / 380.0) * 1.3)

        // Skid volume: drift intensity
        let skidVol: Float = physics.isDrifting ? min(physics.driftIntensity, 1.0) * 0.75 : 0
        skidPlayer?.volume = (skidPlayer?.volume ?? 0) + (skidVol - (skidPlayer?.volume ?? 0)) * 0.1
    }

    private func setupCamera() {
        camera               = SCNCamera()
        camera.fieldOfView   = 65
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
        cameraNode.position  = SCNVector3(0, 5, 12)
        scene.rootNode.addChildNode(cameraNode)
    }

    // MARK: - Frame update (SCNSceneRendererDelegate)

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        // First frame: anchor the timer so it starts at 0
        if firstFrame {
            sessionTime = time
            lapStartTime = time
            firstFrame = false
            return
        }

        let dt = min(Float(time - sessionTime), 1.0 / 30.0)
        sessionTime = time

        // Auto-drive: move car along the spline path directly
        if autoDrive {
            updateAutoDrive(dt: dt, time: time)
            return
        }

        physics.syncFromPhysics(dt: dt)

        // Feed inputs
        physics.throttle = throttleInput
        physics.brake    = brakeInput
        physics.steer    = steerInput
        if selfDrive { updateSelfDrive(time: time) }

        // Off the deck and falling into the city: put the car back on the road.
        let sampleIdx    = track.closestSampleIndex(to: physics.position)
        let nearSample   = track.sample(at: sampleIdx)
        if physics.position.y < nearSample.position.y - 25 { physics.reset(to: nearSample) }
        // On its side or roof for a moment: same.
        physics.groundUp = nearSample.up
        flippedTime = physics.upright < 0.3 ? flippedTime + dt : 0
        if flippedTime > 1 { flippedTime = 0; physics.reset(to: nearSample) }

        // Lap detection
        checkLap(sampleIdx: sampleIdx, time: time)

        // Step physics
        physics.update(dt: dt, world: scene.physicsWorld)

        // Spring-arm camera
        updateCamera(dt: dt)

        // Audio
        updateAudio()

        // HUD read-outs
        displaySpeed    = physics.speedKMH
        displayLap      = lapCount
        displayLapTime  = time - lapStartTime
        displayDrifting = physics.isDrifting
        carWorldPos     = physics.position
    }

    // MARK: - Self-drive (debug)

    private func updateSelfDrive(time: TimeInterval) {
        let here = track.closestSampleIndex(to: physics.position)
        let step = track.totalLength / Float(track.stepCount)
        // Aim at a point further ahead the faster we go.
        let ahead = track.sample(at: here + Int((14 + physics.speed * 0.45) / step))
        let to = ahead.position - physics.position
        let bearing = atan2(to.x, -to.z)
        physics.steer = max(-1, min(1, remainder(bearing - physics.heading, 2 * .pi) * 3))
        // Brake for the tightest curvature within braking distance.
        var tightest: Float = 0
        let reach = Int((30 + physics.speed * 2.2) / step)
        for k in stride(from: 0, to: reach, by: 2) { tightest = max(tightest, abs(track.sample(at: here + k).curvature)) }
        let target = min(CarController.topSpeed, (30 / max(tightest, 1e-4)).squareRoot())
        physics.throttle = physics.speed < target ? 1 : 0
        physics.brake = physics.speed > target + 4 ? 0.8 : 0

        telemetryTop = max(telemetryTop, physics.speed)
        if time - telemetryTime > 2 {
            telemetryTime = time
            print(String(format: "[selfDrive] t=%.0fs lap=%d last=%.1fs progress=%.2f speed=%.0f km/h top=%.0f km/h upright=%.2f",
                         time - lapStartTime, lapCount, lastLapTime, Float(here) / Float(track.stepCount),
                         physics.speedKMH, telemetryTop * 3.6, physics.upright))
        }
    }

    // MARK: - Auto-drive (demo mode)

    private func updateAutoDrive(dt: Float, time: TimeInterval) {
        // Brake for corners: target speed from the tightest curvature in the next 200 m.
        let here = Int(autoDriveProgress * Float(track.stepCount))
        var maxCurv: Float = 0
        for k in stride(from: 0, to: 100, by: 2) { maxCurv = max(maxCurv, abs(track.sample(at: here + k).curvature)) }
        let target = min(CarController.topSpeed, sqrt(34 / max(maxCurv, 1e-4)))
        autoDriveSpeed += max(-34 * dt, min(16 * dt, target - autoDriveSpeed))
        let speed = autoDriveSpeed
        autoDriveProgress += dt * speed / track.totalLength
        if autoDriveProgress >= 1 { autoDriveProgress -= 1 }

        let floatIdx = autoDriveProgress * Float(track.stepCount)
        let idx = Int(floatIdx) % track.stepCount
        let frac = floatIdx - floor(floatIdx)
        let s0 = track.sample(at: idx)
        let s1 = track.sample(at: idx + 1)

        let up = simd_normalize(s0.up + (s1.up - s0.up) * frac)
        let pos = s0.position + (s1.position - s0.position) * frac + up * 0.4
        let fwd = simd_normalize(s0.forward + (s1.forward - s0.forward) * frac)
        let heading = atan2(fwd.x, -fwd.z)
        let right = simd_normalize(simd_cross(fwd, up))

        carNode.simdPosition = pos
        carNode.simdOrientation = simd_quatf(simd_float3x3(columns: (right, simd_cross(right, fwd), -fwd)))
        carNode.animateWheels(speed: speed, steer: 0, dt: dt)

        physics.position = pos
        physics.heading = heading

        // Camera follows
        updateCamera(dt: dt)

        // HUD
        displaySpeed    = speed * 3.6
        displayLap      = 1
        displayLapTime  = time - lapStartTime
        displayDrifting = false
        carWorldPos     = pos
    }

    // MARK: - Camera

    private var cameraYaw: Float?
    private var cameraHeight: Float?

    private func updateCamera(dt: Float) {
        // Smooth only yaw and height; a positional spring would trail further behind at speed.
        var yaw = cameraYaw ?? physics.heading
        let dYaw = remainder(physics.heading - yaw, 2 * Float.pi)
        yaw += dYaw * min(1, 7 * dt)
        cameraYaw = yaw
        let fwd = SIMD3<Float>(sin(yaw), 0, -cos(yaw))

        // NFS3-style chase cam: low and tight behind the car, low enough to clear the gates.
        let behind: Float = 10.2
        let above:  Float = 2.1
        var targetPos = physics.position - fwd * behind + SIMD3<Float>(0, above, 0)
        let ground = scene.physicsWorld.rayTestWithSegment(
            from: SCNVector3(targetPos.x, targetPos.y + 2, targetPos.z),
            to: SCNVector3(targetPos.x, targetPos.y - 100, targetPos.z),
            options: [.collisionBitMask: PhysicsCategory.track,
                      .searchMode: SCNPhysicsWorld.TestSearchMode.closest, .backfaceCulling: false])
        if let hit = ground.first { targetPos.y = max(targetPos.y, Float(hit.worldCoordinates.y) + above) }
        let y = (cameraHeight ?? targetPos.y) + (targetPos.y - (cameraHeight ?? targetPos.y)) * min(1, 8 * dt)
        cameraHeight = y
        cameraNode.simdPosition = SIMD3(targetPos.x, y, targetPos.z)

        // Aim just over the roof so the car sits in the lower third.
        let lookAt = physics.position + fwd * 5 + SIMD3<Float>(0, 1.3, 0)
        cameraNode.simdLook(at: lookAt, up: SIMD3<Float>(0, 1, 0), localFront: SIMD3<Float>(0, 0, -1))

        camera.fieldOfView = CGFloat(60 + min(displaySpeed / 3.6, 110) * 0.2)
    }

    // MARK: - Lap detection

    private func checkLap(sampleIdx: Int, time: TimeInterval) {
        // Wrapped from the last tenth of the lap into the first.
        let n = track.stepCount
        if prevSampleIdx > n * 9 / 10, sampleIdx < n / 10 {
            lapCount += 1
            lastLapTime = time - lapStartTime
            lapStartTime = time
        }
        prevSampleIdx = sampleIdx
    }
}
