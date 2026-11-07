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

    func update(dt: Float) {
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
        let Ffx = rclamp(-frontStiffness           * frontSlip, 7_000)
        let Frx = rclamp(-rearStiff * rearMult     * rearSlip,  7_000)

        // Longitudinal force (forward/backward)
        let Fly = throttle * maxEngineForce
                - brake * maxBrakeForce * (lvFwd > 0 ? 1 : -1)
                - dragCoeff * lvFwd * abs(lvFwd)

        // Transform local forces to world XZ
        velocityStep(dt: dt, fwd: fwd, rgt: rgt, Fly: Fly, Flat: Ffx + Frx)

        // Yaw torque from axle lateral force difference
        let torque = (wheelbase * 0.5) * (Ffx - Frx)
        yawRate += dt * torque / inertia
        yawRate *= max(0, 1 - 2.8 * dt)    // yaw damping
        heading  += dt * yawRate

        // Integrate position
        position.x += dt * vel.x
        position.z += dt * vel.y

        applyToNode(lvFwd: lvFwd, lvRgt: lvRgt)
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
        node.simdEulerAngles = SIMD3<Float>(pitch, heading, roll)
    }

    // Resets the car to a track start position and orientation
    func reset(to sample: PathSample) {
        position  = sample.position + SIMD3<Float>(0, 0.4, 0)
        vel       = .zero
        yawRate   = 0
        // heading so the car faces the track forward direction
        heading   = atan2(sample.forward.x, -sample.forward.z)
    }
}

// Symmetric clamp around ±limit
private func rclamp(_ v: Float, _ limit: Float) -> Float {
    max(-limit, min(limit, v))
}
