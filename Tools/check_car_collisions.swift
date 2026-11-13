import AppKit
import SceneKit
import simd

// Minimal track and car types exercise the production vehicle on a flat surface.
enum SurfaceType { case tarmac, gravel }
struct PathSample {
    var position: SIMD3<Float>
    var forward: SIMD3<Float>
    var up: SIMD3<Float>
}
final class CarNode: SCNNode {
    func preparePhysicsWheels() -> [SCNNode] {
        [SIMD3<Float>(-0.77, 0, -1.2), SIMD3<Float>(0.77, 0, -1.2),
         SIMD3<Float>(-0.77, 0, 0.92), SIMD3<Float>(0.77, 0, 0.92)].map { position in
            let wheel = SCNNode()
            wheel.simdPosition = position
            addChildNode(wheel)
            return wheel
        }
    }
}

@main struct VehicleCheck {
    static func main() {
        let app = NSApplication.shared
        let scene = SCNScene()
        let floor = SCNNode(geometry: SCNBox(width: 1000, height: 1, length: 1000, chamferRadius: 0))
        floor.position.y = -0.5
        floor.physicsBody = SCNPhysicsBody(type: .static, shape: nil)
        floor.physicsBody?.categoryBitMask = PhysicsCategory.track
        floor.physicsBody?.collisionBitMask = PhysicsCategory.car
        scene.rootNode.addChildNode(floor)
        let car = CarNode()
        scene.rootNode.addChildNode(car)
        let controller = CarController()
        controller.install(on: car, in: scene.physicsWorld,
                           at: PathSample(position: .zero, forward: SIMD3(0, 0, -1), up: SIMD3(0, 1, 0)))
        let view = SCNView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        view.scene = scene
        view.isPlaying = true
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        window.makeKeyAndOrderFront(nil)

        var tick = 0
        var movingSpeed: Float = 0
        var startSteerX: Float = 0
        var minBrakingSpeed: Float = .greatestFiniteMagnitude
        var reverseStart = SIMD3<Float>.zero
        var reverseEnd = SIMD3<Float>.zero
        var driveForward = SIMD3<Float>.zero
        Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { timer in
            controller.syncFromPhysics(dt: 1 / 60)
            controller.throttle = tick < 300 || tick >= 480 ? 1 : 0
            controller.steer = (180..<240).contains(tick) ? 0.5 : 0
            controller.brake = (300..<480).contains(tick) ? 1 : 0
            controller.update(dt: 1 / 60, world: scene.physicsWorld)
            if tick == 180 { startSteerX = controller.position.x }
            if tick == 300 { movingSpeed = controller.speed }
            if (300..<390).contains(tick) { minBrakingSpeed = min(minBrakingSpeed, controller.speed) }
            if tick == 390 {
                reverseStart = controller.position
                driveForward = SIMD3(sin(controller.heading), 0, -cos(controller.heading))
            }
            if tick == 480 { reverseEnd = controller.position }
            if tick == 660 {
                let wheelHeights = car.childNodes.map { Float($0.presentation.worldPosition.y) }
                let grounded = wheelHeights.count == 4 && wheelHeights.allSatisfy { (0.25...0.65).contains($0) }
                let forward = controller.position.z < -5 && movingSpeed > 3
                let steering = controller.position.x > startSteerX + 1
                let braking = minBrakingSpeed < movingSpeed * 0.3
                let reverse = simd_dot(reverseEnd - reverseStart, driveForward) < -1
                let forwardAgain = simd_dot(controller.position - reverseEnd, driveForward) > 1
                print("Four wheels grounded: \(grounded ? "pass" : "FAIL")")
                print("Forward acceleration: \(forward ? "pass" : "FAIL")")
                print("Right steering: \(steering ? "pass" : "FAIL")")
                print("Braking: \(braking ? "pass" : "FAIL")")
                print("Automatic reverse: \(reverse ? "pass" : "FAIL")")
                print("Forward after release: \(forwardAgain ? "pass" : "FAIL")")
                fflush(stdout)
                timer.invalidate()
                exit(grounded && forward && steering && braking && reverse && forwardAgain ? 0 : 1)
            }
            tick += 1
        }
        app.run()
    }
}
