/// Sega Rally style arcade physics — bicycle model with per-surface lateral damping.
/// Reference: Marco Monster "Car Physics for Games" (asawicki.info mirror).
///
/// Coordinate system (SceneKit, Y-up right-handed):
///   heading = 0  →  car faces world -Z
///   forward = (sin(h), 0, -cos(h))
///   right   = (cos(h), 0,  sin(h))

import SceneKit
import simd

final class CarController {

    // MARK: - Vehicle constants

    let mass: Float             = 1_100     // kg
    let wheelbase: Float        = 2.6       // m (front–rear axle separation)
    let inertia: Float          = 1_200     // kg·m² yaw
    let maxEngineForce: Float   = 8_000     // N
    let maxBrakeForce: Float    = 12_000    // N
    let dragCoeff: Float        = 0.36      // combined aero + rolling
    let frontStiffness: Float   = 14_000    // N/rad (front axle cornering, stays constant)
    let rearStiffBaseline: Float = 11_500   // N/rad (rear, before surface scale)
    let driftGripFactor: Float  = 0.42      // rear grip fraction when drifting

    // MARK: - Mutable state

    var position    = SIMD3<Float>(0, 0.3, 0)
    var vel         = SIMD2<Float>.zero     // world (x, z) velocity m/s
    var heading: Float = 0                  // yaw rad
    var yawRate: Float = 0                  // rad/s
    private var verticalSpeed: Float = 0
    private(set) var groundNormal = SIMD3<Float>(0, 1, 0)
    private(set) var grounded = false
    private let collisionShape = SCNPhysicsShape(
        geometry: SCNBox(width: 1.9, height: 1.1, length: 3.8, chamferRadius: 0.12), options: nil)

    private(set) var isDrifting     = false
    private(set) var driftIntensity: Float = 0   // 0…1

    var speed: Float    { simd_length(vel) }
    var speedKMH: Float { speed * 3.6 }

    // MARK: - Inputs (set by GameScene each frame before update)

    var throttle: Float = 0     // 0…1
    var brake: Float    = 0     // 0…1
    var steer: Float    = 0     // -1 (left) … +1 (right)
    var surface: SurfaceType = .tarmac

    // The SCNNode this controller drives
    weak var node: SCNNode?

    // MARK: - Physics step

    func update(dt: Float, world: SCNPhysicsWorld) {
        let fwd = SIMD2<Float>( sin(heading), -cos(heading))   // world (x,z)
        let rgt = SIMD2<Float>( cos(heading),  sin(heading))

        // Local velocity components
        let lvFwd = simd_dot(vel, fwd)
        let lvRgt = simd_dot(vel, rgt)
        let sFwd  = max(abs(lvFwd), 1.5)    // prevent /0 at standstill

        // Steering angle of front wheels
        let steerAngle = steer * 0.52       // ±0.52 rad ≈ ±30°

        // Slip angles (bicycle model — both wheels on the centreline)
        let frontSlip = atan2(lvRgt + yawRate * wheelbase * 0.5, sFwd) - steerAngle
        let rearSlip  = atan2(lvRgt - yawRate * wheelbase * 0.5, sFwd)

        // Per-surface rear cornering stiffness (surface.corneringStiffness is tarmac-normalised)
        let rearStiff = rearStiffBaseline * (surface.corneringStiffness / 15_000)

        // Rear drift detection
        let driftThr  = surface.driftThreshold
        isDrifting    = abs(rearSlip) > driftThr && speed > 10
        driftIntensity = isDrifting ? min((abs(rearSlip) - driftThr) / 0.4, 1.0) : 0
        let rearMult: Float = isDrifting ? driftGripFactor : 1.0

        // Lateral forces in local car space
        let grip: Float = grounded ? 1 : 0
        let Ffx = rclamp(-frontStiffness           * frontSlip, 7_000) * grip
        let Frx = rclamp(-rearStiff * rearMult     * rearSlip,  7_000) * grip

        // Longitudinal force (forward/backward)
        let Fly = (throttle * maxEngineForce
                - brake * maxBrakeForce * (lvFwd > 0 ? 1 : -1)) * grip
                - dragCoeff * lvFwd * abs(lvFwd)

        // Transform local forces to world XZ
        velocityStep(dt: dt, fwd: fwd, rgt: rgt, Fly: Fly, Flat: Ffx + Frx)
        if grounded {
            // Gravity projected along the contacted slope makes hills affect momentum.
            vel += SIMD2(groundNormal.x, groundNormal.z) * (9.81 * groundNormal.y * dt)
        }

        // Yaw torque from axle lateral force difference
        let torque = (wheelbase * 0.5) * (Ffx - Frx)
        yawRate += dt * torque / inertia
        yawRate *= max(0, 1 - 2.8 * dt)    // yaw damping
        heading  += dt * yawRate

        // Integrate position
        moveAgainstObstacles(dt: dt, world: world)
        updateGround(dt: dt, world: world)

        applyToNode(lvFwd: lvFwd, lvRgt: lvRgt)
    }

    private func moveAgainstObstacles(dt: Float, world: SCNPhysicsWorld) {
        var remaining = SIMD3<Float>(vel.x * dt, 0, vel.y * dt)
        let options: [SCNPhysicsWorld.TestOption: Any] = [
            .collisionBitMask: PhysicsCategory.obstacle,
            .searchMode: SCNPhysicsWorld.TestSearchMode.closest,
            .backfaceCulling: false,
        ]
        func transform(_ p: SIMD3<Float>) -> SCNMatrix4 {
            var matrix = simd_float4x4(simd_quatf(angle: -heading, axis: SIMD3(0, 1, 0)))
            matrix.columns.3 = SIMD4(p.x, p.y + 0.3, p.z, 1)
            return SCNMatrix4(matrix)
        }
        for _ in 0..<3 {
            guard simd_length_squared(remaining) > 1e-8 else { break }
            let hits = world.convexSweepTest(with: collisionShape, from: transform(position),
                                             to: transform(position + remaining), options: options)
            guard let hit = hits.first else { position += remaining; break }
            let fraction = max(0, Float(hit.sweepTestFraction) - 0.01)
            position += remaining * fraction
            var normal = SIMD2<Float>(Float(hit.contactNormal.x), Float(hit.contactNormal.z))
            let length = simd_length(normal)
            guard length > 0.001 else { break }
            normal /= length
            if simd_dot(normal, SIMD2(remaining.x, remaining.z)) > 0 { normal = -normal }
            let inward = simd_dot(vel, normal)
            if inward < 0 { vel -= normal * inward * 1.05 }
            vel *= 0.86
            yawRate *= 0.5
            let rest = SIMD2(remaining.x, remaining.z) * (1 - fraction)
            let slide = rest - normal * min(0, simd_dot(rest, normal))
            remaining = SIMD3(slide.x, 0, slide.y) * 0.86
        }
    }

    private func updateGround(dt: Float, world: SCNPhysicsWorld) {
        let from = SCNVector3(position.x, position.y + 2, position.z)
        let to = SCNVector3(position.x, position.y - 100, position.z)
        let hits = world.rayTestWithSegment(from: from, to: to, options: [
            .collisionBitMask: PhysicsCategory.track | PhysicsCategory.terrain,
            .searchMode: SCNPhysicsWorld.TestSearchMode.closest,
            .backfaceCulling: false,
        ])
        verticalSpeed -= 24 * dt
        let nextY = position.y + verticalSpeed * dt
        if let hit = hits.first, nextY <= Float(hit.worldCoordinates.y) + 0.4 {
            position.y = Float(hit.worldCoordinates.y) + 0.4
            verticalSpeed = 0
            var normal = SIMD3<Float>(Float(hit.worldNormal.x), Float(hit.worldNormal.y), Float(hit.worldNormal.z))
            if normal.y < 0 { normal = -normal }
            if simd_length_squared(normal) > 0.01 { groundNormal = simd_normalize(normal) }
            grounded = true
        } else {
            position.y = nextY
            grounded = false
        }
    }

    private func velocityStep(dt: Float, fwd: SIMD2<Float>, rgt: SIMD2<Float>,
                               Fly: Float, Flat: Float) {
        let wx = Fly * fwd.x + Flat * rgt.x
        let wz = Fly * fwd.y + Flat * rgt.y
        vel.x += dt * wx / mass
        vel.y += dt * wz / mass

        let spd = speed
        let maxSpd: Float = 68   // ≈ 245 km/h
        if spd > maxSpd { vel *= maxSpd / spd }
    }

    private func applyToNode(lvFwd: Float, lvRgt _: Float) {
        guard let node = node else { return }
        node.simdPosition = position

        // Cosmetic weight-transfer tilt
        let pitch = -lvFwd / 220.0
        let roll  = -yawRate * 0.075
        node.simdEulerAngles = SIMD3<Float>(pitch, -heading, roll)
    }

    // Resets the car to a track start position and orientation
    func reset(to sample: PathSample) {
        position  = sample.position + SIMD3<Float>(0, 0.4, 0)
        vel       = .zero
        yawRate   = 0
        verticalSpeed = 0
        groundNormal = SIMD3(0, 1, 0)
        grounded = false
        // heading so the car faces the track forward direction
        heading   = atan2(sample.forward.x, -sample.forward.z)
    }
}

// Symmetric clamp around ±limit
private func rclamp(_ v: Float, _ limit: Float) -> Float {
    max(-limit, min(limit, v))
}
