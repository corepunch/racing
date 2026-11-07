import SceneKit
import SpriteKit
import simd
import AVFoundation

/// Main game orchestrator.  Owns the SCNScene, track, car controller, camera,
/// lap timing, and the per-frame physics loop via SCNSceneRendererDelegate.
final class GameScene: NSObject, SCNSceneRendererDelegate {

    let scene = SCNScene()

    // --- Sub-systems ---
    let track             = TrackPath()
    private let physics   = CarController()
    private var carNode: CarNode!

    // --- Car style (change to any CarStyle case to swap the visual model) ---
    var carStyle: CarStyle = .truckGreen

    // --- Audio ---
    private var enginePlayer: AVAudioPlayer?
    private var skidPlayer:   AVAudioPlayer?
    private var cameraNode: SCNNode!
    private var camera: SCNCamera!

    // --- Inputs (set by GameViewController / InputManager) ---
    var throttleInput: Float = 0
    var brakeInput: Float    = 0
    var steerInput: Float    = 0

    // --- Demo auto-drive ---
    var autoDrive = false
    private var autoDriveProgress: Float = 0

    // --- Lap state ---
    private var lapCount       = 0
    private var lapStartTime: TimeInterval = 0
    private var lastLapTime: TimeInterval  = 0
    private var sessionTime: TimeInterval  = 0
    private var firstFrame     = true
    private var prevSampleIdx  = 0
    private var lapArcStart: Float = 0
    private var crossedStart   = false

    // HUD read-outs (GameViewController polls these)
    private(set) var displaySpeed: Float    = 0
    private(set) var displayLap: Int        = 0
    private(set) var displayLapTime: TimeInterval = 0
    private(set) var displaySurface: SurfaceType = .tarmac
    private(set) var displayDrifting        = false
    private(set) var carWorldPos: SIMD3<Float> = .zero

    // MARK: - Init

    override init() {
        super.init()
        buildScene()
    }

    // MARK: - Scene setup

    private func buildScene() {
        scene.background.contents   = UIColor(red: 0.56, green: 0.80, blue: 0.95, alpha: 1)
        scene.fogStartDistance      = 320
        scene.fogEndDistance        = 520
        scene.fogColor              = UIColor(red: 0.70, green: 0.85, blue: 0.95, alpha: 1)

        addLighting()

        // Track mesh
        let trackNode = TrackMeshBuilder.buildTrackNode(path: track)
        scene.rootNode.addChildNode(trackNode)

        // Decorations
        TrackDecorations.addDecorations(to: scene.rootNode, path: track)

        // Ground plane beyond the track ribbon (simple grass)
        addGround()

        // Car
        carNode = CarNode(style: carStyle)
        let startSample = track.samples[0]
        physics.reset(to: startSample)
        carNode.simdPosition = physics.position
        physics.node = carNode
        scene.rootNode.addChildNode(carNode)

        // Camera
        setupCamera()

        // Audio
        setupAudio()
    }

    private func addLighting() {
        // Sun
        let sunLight         = SCNLight()
        sunLight.type        = .directional
        sunLight.color       = UIColor(red: 1.0, green: 0.96, blue: 0.84, alpha: 1)
        sunLight.intensity   = 1_200
        sunLight.castsShadow = true
        sunLight.shadowMode  = .deferred
        sunLight.shadowSampleCount = 4
        let sunNode          = SCNNode()
        sunNode.light        = sunLight
        sunNode.eulerAngles  = SCNVector3(-Float.pi / 4.5, Float.pi / 6, 0)
        scene.rootNode.addChildNode(sunNode)

        // Sky fill
        let ambLight         = SCNLight()
        ambLight.type        = .ambient
        ambLight.color       = UIColor(red: 0.60, green: 0.70, blue: 0.90, alpha: 1)
        ambLight.intensity   = 400
        let ambNode          = SCNNode()
        ambNode.light        = ambLight
        scene.rootNode.addChildNode(ambNode)
    }

    private func addGround() {
        let floor            = SCNFloor()
        floor.reflectivity   = 0
        let mat              = SCNMaterial()
        mat.diffuse.contents = UIColor(red: 0.25, green: 0.42, blue: 0.18, alpha: 1)
        mat.roughness.contents = 1.0
        floor.firstMaterial  = mat
        let node             = SCNNode(geometry: floor)
        node.position        = SCNVector3(0, -0.02, 0)
        node.physicsBody     = SCNPhysicsBody(type: .static, shape: nil)
        node.physicsBody?.categoryBitMask  = PhysicsCategory.track
        node.physicsBody?.collisionBitMask = PhysicsCategory.car
        scene.rootNode.addChildNode(node)
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
        enginePlayer?.rate   = 0.6 + Float(spd / 200.0) * 0.8

        // Skid volume: drift intensity
        let skidVol: Float = physics.isDrifting ? min(physics.driftIntensity, 1.0) * 0.75 : 0
        skidPlayer?.volume = (skidPlayer?.volume ?? 0) + (skidVol - (skidPlayer?.volume ?? 0)) * 0.1
    }

    private func setupCamera() {
        camera               = SCNCamera()
        camera.fieldOfView   = 65
        camera.zFar          = 600
        camera.zNear         = 0.5

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

        // Feed inputs
        physics.throttle = throttleInput
        physics.brake    = brakeInput
        physics.steer    = steerInput

        // Surface lookup
        let sampleIdx    = track.closestSampleIndex(to: physics.position)
        let nearSample   = track.sample(at: sampleIdx)
        physics.surface  = nearSample.surface

        // Keep car at road height (simple Y projection from closest sample)
        physics.position.y = nearSample.position.y + 0.4

        // Lap detection
        checkLap(sampleIdx: sampleIdx, time: time)

        // Step physics
        physics.update(dt: dt)

        // Wheel animation
        carNode?.animateWheels(speed: physics.speed, steer: steerInput, dt: dt)

        // Spring-arm camera
        updateCamera(dt: dt)

        // Audio
        updateAudio()

        // HUD read-outs
        displaySpeed    = physics.speedKMH
        displayLap      = lapCount
        displayLapTime  = time - lapStartTime
        displaySurface  = nearSample.surface
        displayDrifting = physics.isDrifting
        carWorldPos     = physics.position
    }

    // MARK: - Auto-drive (demo mode)

    private func updateAutoDrive(dt: Float, time: TimeInterval) {
        let speed: Float = 45   // m/s ≈ 162 km/h
        autoDriveProgress += dt * speed / track.totalLength
        if autoDriveProgress >= 1 { autoDriveProgress -= 1 }

        let floatIdx = autoDriveProgress * Float(track.stepCount)
        let idx = Int(floatIdx) % track.stepCount
        let frac = floatIdx - floor(floatIdx)
        let s0 = track.sample(at: idx)
        let s1 = track.sample(at: idx + 1)

        let pos = s0.position + (s1.position - s0.position) * frac + SIMD3<Float>(0, 0.4, 0)
        let fwd = simd_normalize(s0.forward + (s1.forward - s0.forward) * frac)
        let heading = atan2(fwd.x, -fwd.z)

        carNode.simdPosition = pos
        carNode.simdEulerAngles = SIMD3<Float>(0, -heading, 0)
        carNode.animateWheels(speed: speed, steer: 0, dt: dt)

        physics.position = pos
        physics.heading = heading

        // Camera follows
        updateCamera(dt: dt)

        // HUD
        displaySpeed    = speed * 3.6
        displayLap      = 1
        displayLapTime  = time - lapStartTime
        displaySurface  = s0.surface
        displayDrifting = false
        carWorldPos     = pos
    }

    // MARK: - Camera

    private func updateCamera(dt: Float) {
        let h   = physics.heading
        let fwd = SIMD3<Float>(sin(h), 0, -cos(h))

        // CTR-style: farther back, higher, looking well ahead
        let behind: Float = 16.0
        let above:  Float = 7.5
        let targetPos = physics.position - fwd * behind + SIMD3<Float>(0, above, 0)

        // Spring follow (smoothing proportional to frame time)
        let alpha: Float = min(1.0, 5.5 * dt)
        let cur   = SIMD3<Float>(Float(cameraNode.position.x),
                                  Float(cameraNode.position.y),
                                  Float(cameraNode.position.z))
        let next  = cur + (targetPos - cur) * alpha
        cameraNode.simdPosition = next

        // Look ahead of car (more forward offset gives road-preview feel)
        let lookAt = physics.position + fwd * 14 + SIMD3<Float>(0, 0.6, 0)
        cameraNode.simdLook(at: lookAt, up: SIMD3<Float>(0, 1, 0), localFront: SIMD3<Float>(0, 0, -1))

        // Slight FOV boost at speed (Sega Rally "rushing" feel)
        camera.fieldOfView = CGFloat(68 + physics.speed * 0.14)
    }

    // MARK: - Lap detection

    private func checkLap(sampleIdx: Int, time: TimeInterval) {
        let progress = Float(sampleIdx) / Float(track.stepCount)

        if !crossedStart && progress < 0.05 && prevSampleIdx > track.stepCount - 20 {
            // Car wrapped from near end back to start
            lapCount += 1
            lastLapTime = time - lapStartTime
            lapStartTime = time
        }
        crossedStart = progress > 0.08
        prevSampleIdx = sampleIdx
    }
}
