import SceneKit
import simd

/// Four-wheel-drive arcade racer. Dimensions follow the displayed car's wheel locations;
/// power, grip and downforce are tuned for speed, not realism: about 380 km/h flat out.
final class CarController {
    let mass: CGFloat = 1_900
    private let engineForce: CGFloat = 34_000
    /// About 1.1 g on its own; split front-biased so the car squats rather than tips.
    private let brakeForce: CGFloat = 21_000
    /// Speed (m/s) at which drive force has faded to nothing.
    static let topSpeed: Float = 106
    /// Aerodynamic grip in N per (m/s)², pressing the car into the road.
    private let downforce: Float = 3.2
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
    /// Road normal under the car; the chassis is held towards it so it cannot roll over.
    var groundUp = SIMD3<Float>(0, 1, 0)
    /// 1 when the car sits flat on the road, negative when it is on its roof.
    private(set) var upright: Float = 1
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
        body.centerOfMassOffset = SCNVector3(0, -0.35, 0)
        body.categoryBitMask = PhysicsCategory.car
        body.collisionBitMask = PhysicsCategory.track | PhysicsCategory.terrain | PhysicsCategory.obstacle
        body.friction = 0.6
        body.restitution = 0
        body.damping = 0.02
        body.angularDamping = 0.7
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
            wheel.suspensionStiffness = 55
            wheel.suspensionCompression = 6.5
            wheel.suspensionDamping = 8
            wheel.maximumSuspensionForce = 40_000
            wheel.frictionSlip = 5.5
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
        // Thrust fades towards top speed; reverse is deliberately weak.
        let fade = CGFloat(max(0, 1 - pow(speed / Self.topSpeed, 2)))
        let drive: CGFloat = changingDirection ? 0 : (reversing ? CGFloat(brake) * 0.25 : -CGFloat(throttle) * fade)
        let braking: CGFloat = changingDirection ? (wantsReverse ? CGFloat(brake) : 1) : 0
        // Steering lock shrinks with speed so the car stays controllable at 100 m/s.
        let speedFactor = max(0.1, 1 / (1 + speed / 20))
        let steering = CGFloat(-steer * 0.55 * speedFactor)
        if let body = node?.physicsBody, let transform = node?.presentation.simdWorldTransform {
            let up = SIMD3<Float>(transform.columns.1.x, transform.columns.1.y, transform.columns.1.z)
            let push = -up * (downforce * speed * speed)
            body.applyForce(SCNVector3(push.x, push.y, push.z), asImpulse: false)
            // Righting moment: proportional to the tilt away from the road normal.
            upright = simd_dot(up, groundUp)
            let tilt = simd_cross(up, groundUp)
            let amount = simd_length(tilt)
            if amount > 1e-4 {
                let axis = tilt / amount
                body.applyTorque(SCNVector4(axis.x, axis.y, axis.z, amount * 42_000), asImpulse: false)
            }
            applyStabilityAssist(body: body, up: up, transform: transform, steering: Float(steering))
        }
        for index in 0..<4 {
            let front = index < 2
            vehicle.setSteeringAngle(front ? steering : 0, forWheelAt: index)
            vehicle.applyEngineForce(engineForce * drive / 4, forWheelAt: index)
            vehicle.applyBrakingForce(brakeForce * braking * (front ? 0.3 : 0.2), forWheelAt: index)
        }
    }

    /// Driver aids: damps pitch and roll so the car cannot tip over, trims yaw beyond what
    /// the steering asks for so it does not spin, and bleeds off sideways slide.
    private func applyStabilityAssist(body: SCNPhysicsBody, up: SIMD3<Float>, transform: simd_float4x4, steering: Float) {
        guard upright > 0.5 else { return }
        let av = body.angularVelocity
        let omega = SIMD3<Float>(Float(av.x), Float(av.y), Float(av.z)) * Float(av.w)
        let yawRate = simd_dot(omega, up)
        let tumble = omega - up * yawRate
        let tumbleRate = simd_length(tumble)
        if tumbleRate > 1e-3 {
            let axis = -tumble / tumbleRate
            body.applyTorque(SCNVector4(axis.x, axis.y, axis.z, tumbleRate * 9_000), asImpulse: false)
        }
        // Expected yaw rate for this steering angle on a 2.6 m wheelbase, plus a little slack.
        let expected = speed * abs(tan(steering)) / 2.6
        let excess = abs(yawRate) - expected - 0.15
        if excess > 0 {
            let axis = up * (yawRate > 0 ? -1 : 1)
            body.applyTorque(SCNVector4(axis.x, axis.y, axis.z, excess * 7_000), asImpulse: false)
        }
        guard speed > 3 else { return }
        let right = SIMD3<Float>(transform.columns.0.x, transform.columns.0.y, transform.columns.0.z)
        let v = body.velocity
        let sideways = simd_dot(SIMD3<Float>(Float(v.x), Float(v.y), Float(v.z)), right)
        let grip = -right * sideways * Float(mass) * 1.6
        body.applyForce(SCNVector3(grip.x, grip.y, grip.z), asImpulse: false)
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
