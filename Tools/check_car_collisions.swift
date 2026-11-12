import AppKit
import SceneKit
import simd

// Minimal track types let this exercise the production controller on macOS.
enum SurfaceType {
    case tarmac
    var corneringStiffness: Float { 15_000 }
    var driftThreshold: Float { 0.3 }
}
struct PathSample {
    var position: SIMD3<Float>
    var forward: SIMD3<Float>
}

@main struct CollisionCheck {
    static func main() {
        let app = NSApplication.shared
        let scene = SCNScene()
        let floor = SCNNode(geometry: SCNBox(width: 100, height: 1, length: 100, chamferRadius: 0))
        floor.position.y = -0.5
        PhysicsCategory.addStaticMesh(to: floor, category: PhysicsCategory.terrain)
        scene.rootNode.addChildNode(floor)

        let wall = SCNNode(geometry: SCNBox(width: 10, height: 4, length: 0.2, chamferRadius: 0))
        wall.position = SCNVector3(0, 1, -8)
        wall.opacity = 0 // Tree trunk collision geometry is transparent too.
        PhysicsCategory.addStaticMesh(to: wall, category: PhysicsCategory.obstacle)
        scene.rootNode.addChildNode(wall)

        let ramp = SCNNode(geometry: SCNBox(width: 8, height: 0.5, length: 8, chamferRadius: 0))
        ramp.position = SCNVector3(20, 1.5, 0)
        ramp.eulerAngles.z = 0.2
        PhysicsCategory.addStaticMesh(to: ramp, category: PhysicsCategory.track)
        scene.rootNode.addChildNode(ramp)

        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.position.z = 20
        scene.rootNode.addChildNode(camera)
        let view = SCNView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        view.scene = scene
        view.pointOfView = camera
        view.isPlaying = true
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        window.makeKeyAndOrderFront(nil)

        // SceneKit registers static bodies as its renderer starts.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            let car = CarController()
            car.position = SIMD3(0, 3, 0)
            for _ in 0..<180 { car.update(dt: 1 / 60, world: scene.physicsWorld) }
            let landed = car.grounded && abs(car.position.y - 0.4) < 0.1
            print("Ground contact: \(landed ? "pass" : "FAIL")")

            car.vel = SIMD2(0, -60)
            for _ in 0..<30 { car.update(dt: 1 / 60, world: scene.physicsWorld) }
            let stopped = car.position.z > -7 && car.speed < 10
            print("High-speed transparent obstacle: \(stopped ? "pass" : "FAIL")")

            let hillCar = CarController()
            hillCar.position = SIMD3(20, 2.2, 0)
            for _ in 0..<10 { hillCar.update(dt: 1 / 60, world: scene.physicsWorld) }
            let slope = hillCar.grounded && hillCar.groundNormal.x < -0.1 && hillCar.vel.x < 0
            print("Slope normal and downhill gravity: \(slope ? "pass" : "FAIL")")
            fflush(stdout)
            exit(landed && stopped && slope ? 0 : 1)
        }
        app.run()
    }
}
