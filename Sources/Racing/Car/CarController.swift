import SceneKit
import simd

/// Four-wheel-drive vehicle. Dimensions follow the displayed truck's wheel locations;
/// mass and drivetrain are approximations of a two-door Jeep Wrangler.
final class CarController {
    let mass: CGFloat = 1_900
    private let engineForce: CGFloat = 8_000
    private let brakeForce: CGFloat = 14_000
    private var vehicle: SCNPhysicsVehicle?
    private weak var node: CarNode?
    private weak var world: SCNPhysicsWorld?
    private var isDemo = false
    private var previousPosition: SIMD3<Float>?
    private var reversing = false

    var position = SIMD3<Float>.zero
    var heading: Float = 0
    var throttle: Float = 0
    var brake: Float = 0
    var steer: Float = 0
    var surface: SurfaceType = .tarmac
    private(set) var isDrifting = false
    private(set) var driftIntensity: Float = 0
    var speed: Float { abs(Float(vehicle?.speedInKilometersPerHour ?? 0)) / 3.6 }
    var speedKMH: Float { speed * 3.6 }

    func install(on car: CarNode, in world: SCNPhysicsWorld, at sample: PathSample) {
        node = car
        self.world = world
        let chassisShape = SCNPhysicsShape(geometry: SCNBox(width: 1.65, height: 0.65, length: 3.25, chamferRadius: 0.12),
                                           options: nil)
        // The visual car's origin is at axle height; the box is above the wheels.
        let shape = SCNPhysicsShape(shapes: [chassisShape], transforms: [NSValue(scnMatrix4: SCNMatrix4MakeTranslation(0, 0.55, 0))])
        let body = SCNPhysicsBody(type: .dynamic, shape: shape)
        body.mass = mass
        body.centerOfMassOffset = SCNVector3(0, 0.25, 0)
        body.categoryBitMask = PhysicsCategory.car
        body.collisionBitMask = PhysicsCategory.track | PhysicsCategory.terrain | PhysicsCategory.obstacle
        body.friction = 0.6
        body.restitution = 0
        body.damping = 0.05
        body.angularDamping = 0.5
        car.physicsBody = body

        let wheelNodes = car.preparePhysicsWheels()
        let wheels = wheelNodes.map { wheelNode -> SCNPhysicsVehicleWheel in
            let wheel = SCNPhysicsVehicleWheel(node: wheelNode)
            wheel.connectionPosition = SCNVector3(wheelNode.position.x, wheelNode.position.y + 0.28, wheelNode.position.z)
            wheel.axle = SCNVector3(-1, 0, 0)
            wheel.steeringAxis = SCNVector3(0, -1, 0)
            wheel.radius = 0.42
            wheel.suspensionRestLength = 0.28
            wheel.maximumSuspensionTravel = 20 // centimetres
            wheel.suspensionStiffness = 30
            wheel.suspensionCompression = 4.4
            wheel.suspensionDamping = 5.5
            wheel.maximumSuspensionForce = 12_000
            wheel.frictionSlip = 2.5
            return wheel
        }
        let vehicle = SCNPhysicsVehicle(chassisBody: body, wheels: wheels)
        self.vehicle = vehicle
        reset(to: sample)
        world.addBehavior(vehicle)
    }

    func setDemo(_ enabled: Bool) {
        guard isDemo != enabled, let vehicle = vehicle, let body = node?.physicsBody, let world = world else { return }
        isDemo = enabled
        if enabled {
            world.removeBehavior(vehicle)
            body.type = .kinematic
        } else {
            body.type = .dynamic
            body.resetTransform()
            world.addBehavior(vehicle)
        }
    }

    func reset(to sample: PathSample) {
        let up = simd_normalize(sample.up)
        let forward = simd_normalize(sample.forward)
        let right = simd_normalize(simd_cross(forward, up))
        position = sample.position + up * 0.8
        previousPosition = nil
        reversing = false
        heading = atan2(forward.x, -forward.z)
        node?.simdPosition = position
        node?.simdOrientation = simd_quatf(simd_float3x3(columns: (right, simd_cross(right, forward), -forward)))
        node?.physicsBody?.velocity = SCNVector3Zero
        node?.physicsBody?.angularVelocity = SCNVector4Zero
        node?.physicsBody?.resetTransform()
    }

    /// Apply wheel forces before SceneKit advances the physics world.
    func update(dt: Float, world: SCNPhysicsWorld) {
        guard let vehicle = vehicle else { return }
        // Holding brake switches to reverse once the car is nearly stopped.
        // Releasing it brakes reverse motion before automatic forward drive resumes.
        let wantsReverse = brake > 0.1
        if wantsReverse && !reversing && speed < 0.5 { reversing = true }
        if !wantsReverse && reversing && speed < 0.5 { reversing = false }
        let changingDirection = wantsReverse != reversing
        let drive: CGFloat = changingDirection ? 0 : (reversing ? CGFloat(brake) : -CGFloat(throttle))
        let braking: CGFloat = changingDirection ? (wantsReverse ? CGFloat(brake) : 1) : 0
        let speedFactor = max(0.35, 1 - speed / 65)
        let steering = CGFloat(-steer * 0.55 * speedFactor)
        for index in 0..<4 {
            vehicle.setSteeringAngle(index < 2 ? steering : 0, forWheelAt: index)
            vehicle.applyEngineForce(engineForce * drive / 4, forWheelAt: index)
            vehicle.applyBrakingForce(brakeForce * braking / 4, forWheelAt: index)
            vehicle.wheels[index].frictionSlip = surface == .tarmac ? 2.5 : 1.6
        }
    }

    /// Read SceneKit's simulated pose after the physics step.
    func syncFromPhysics(dt: Float) {
        guard let node = node else { return }
        let transform = node.presentation.simdWorldTransform
        position = transform.columns.3.xyz
        let velocity = previousPosition.map { (position - $0) / max(dt, 0.001) } ?? .zero
        previousPosition = position
        let forward = -SIMD3<Float>(transform.columns.2.x, transform.columns.2.y, transform.columns.2.z)
        heading = atan2(forward.x, -forward.z)
        let lateral = SIMD3<Float>(transform.columns.0.x, transform.columns.0.y, transform.columns.0.z)
        let sideways = abs(simd_dot(velocity, lateral))
        driftIntensity = min(1, max(0, (sideways - 2) / 6))
        isDrifting = speed > 10 && driftIntensity > 0
    }
}

private extension SIMD4 where Scalar == Float {
    var xyz: SIMD3<Float> { SIMD3(x, y, z) }
}
