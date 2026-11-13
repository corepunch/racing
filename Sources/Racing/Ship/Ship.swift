import SceneKit
import simd

struct ShipInput {
    /// −1 (left) ... 1 (right).
    var steer: Float = 0
    /// 0 ... 1 airbrake: slows the ship and tightens its turn.
    var brake: Float = 0
}

/// One hover-ship, player or rival. It lives in the track's own frame: a distance round
/// the lap, a lateral offset from the centre line and a heading relative to the road.
/// That keeps it glued to the deck over hills and banking, and makes the walls a simple
/// limit on the offset. Nothing here follows the road for the pilot: with no steering
/// the ship flies straight and the road turns away underneath it.
final class Ship {
    let design: ShipDesign
    let node = SCNNode()
    private let body: SCNNode

    // --- State in the track frame ---
    /// Distance round the lap in metres, wrapped.
    private(set) var s: Float = 0
    /// Total distance since the start line; negative on the grid.
    private(set) var progress: Float = 0
    /// Lateral offset in metres, positive to the right.
    private(set) var d: Float = 0
    private(set) var speed: Float = 0
    /// Nose angle relative to the road, positive pointing right.
    private(set) var heading: Float = 0
    /// Direction of travel relative to the road. Lags the nose: that is the slide.
    private(set) var travel: Float = 0
    private(set) var yawRate: Float = 0
    /// Seconds of boost left.
    private(set) var boost: Float = 0
    private(set) var scraping = false
    /// Strongest wall hit (m/s into the wall) since last read.
    var pendingHit: Float = 0
    var pendingBoost = false

    // --- Race bookkeeping (owned by GameScene) ---
    var finishTime: Float?
    var lapStart: Float = 0
    var bestLap: Float?
    var lastLap: Float?

    // --- Rival driver ---
    /// Preferred lateral offset, and a pace factor on top speed.
    var lane: Float = 0
    var pace: Float = 1
    var avoid: Float = 0

    private(set) var worldPosition = SIMD3<Float>.zero
    /// World yaw of the direction of travel, for the camera.
    private(set) var worldForward = SIMD3<Float>(0, 0, -1)
    private var bob: Float = 0

    static let halfWidth: Float = 1.3
    static let hoverHeight: Float = 0.75
    static let boostTime: Float = 2.2

    init(design: ShipDesign) {
        self.design = design
        body = ShipMesh.build(design)
        node.addChildNode(body)
        bob = Float(design.seed % 7)
    }

    func place(progress: Float, lateral: Float, on track: TrackPath) {
        self.progress = progress
        s = Self.wrap(progress, track.totalLength)
        d = lateral
        speed = 0; heading = 0; travel = 0; yawRate = 0; boost = 0
        scraping = false; pendingHit = 0; pendingBoost = false
        finishTime = nil; lapStart = 0; bestLap = nil; lastLap = nil; avoid = 0
        updateNode(track.frame(at: s), dt: 0)
    }

    private static func wrap(_ x: Float, _ length: Float) -> Float {
        let r = x.truncatingRemainder(dividingBy: length)
        return r < 0 ? r + length : r
    }

    /// Yaw rate available at this speed and airbrake.
    func authority(brake: Float) -> Float {
        design.spec.agility * (1 + 0.45 * brake) * min(1, 0.3 + speed / 28)
    }

    func giveBoost() {
        if boost < Self.boostTime * 0.5 { pendingBoost = true }
        boost = Self.boostTime
    }

    /// Sideways shove from another ship.
    func nudge(lateral: Float, speedScale: Float) {
        d += lateral
        speed *= speedScale
    }

    /// Advances the ship by `dt`. `wallGuard` (0...1) is the pilot assist: see `guardYaw`.
    func step(dt: Float, input: ShipInput, track: TrackPath, throttle: Float = 1, wallGuard: Float = 0) {
        let spec = design.spec
        let frame = track.frame(at: s)
        let k = frame.curvature
        let limit = frame.halfWidth - Self.halfWidth
        let boosting = boost > 0
        boost = max(0, boost - dt)
        let top = spec.topSpeed * pace * (boosting ? 1.22 : 1)

        // Steering sets a yaw rate; the nose answers in about a tenth of a second.
        let reach = authority(brake: input.brake)
        var wanted = max(-1, min(1, input.steer)) * reach
        if wallGuard > 0 { wanted += guardYaw(limit: limit, reach: reach) * wallGuard }
        yawRate += (wanted - yawRate) * min(1, 9 * dt)

        // The road turns under the ship: both angles are measured against it.
        let advance = speed * cos(travel) / max(0.5, 1 - d * k)
        let turn = k * advance * dt
        heading += yawRate * dt - turn
        travel -= turn
        travel += (heading - travel) * min(1, spec.grip * dt)
        // The nose can never come round to face backwards.
        heading = max(-1.15, min(1.15, heading))
        travel = max(-1.15, min(1.15, travel))

        // Thrust fades towards top speed; sliding and the airbrake scrub speed off.
        let slip = abs(sin(heading - travel))
        let ratio = speed / top
        var acceleration = spec.thrust * (boosting ? 1.9 : 1) * throttle * (1 - input.brake) * max(0, 1 - ratio * ratio)
        if speed > top { acceleration -= (speed - top) * 1.4 }
        acceleration -= speed * slip * 0.34
        acceleration -= input.brake * 34
        if throttle < 1 { acceleration -= (1 - throttle) * speed * 0.6 }
        speed = max(0, speed + acceleration * dt)

        let distance = advance * dt
        progress += distance
        s = Self.wrap(s + distance, track.totalLength)
        d += speed * sin(travel) * dt

        // Barriers: a glancing touch slides along the wall, a square hit costs real speed.
        scraping = false
        if abs(d) > limit {
            let side: Float = d > 0 ? 1 : -1
            d = side * limit
            let into = sin(travel) * side
            if into > 0 {
                let impact = into * speed
                if impact > 2.5 {
                    speed *= 1 - min(0.5, into * 1.15) * (1 - 0.6 * spec.shield)
                    pendingHit = max(pendingHit, impact)
                }
                travel = -side * 0.02
            }
            if heading * side > 0 { heading -= heading * min(1, 7 * dt) }
            speed -= speed * 0.55 * (1 - 0.5 * spec.shield) * dt
            scraping = true
        }

        updateNode(track.frame(at: s), dt: dt)
    }

    /// The optional pilot assist. It never steers along the road: it only looks at how
    /// fast the ship is closing on a barrier and, in the last half second before contact,
    /// leans the nose away by at most a third of the steering authority. Enough to turn
    /// a crash into a graze, not enough to take a corner.
    private func guardYaw(limit: Float, reach: Float) -> Float {
        let lateral = speed * sin(travel)
        guard abs(lateral) > 1.5 else { return 0 }
        let side: Float = lateral > 0 ? 1 : -1
        let room = max(0, limit - d * side)
        let timeToWall = room / abs(lateral)
        let window: Float = 0.55
        guard timeToWall < window else { return 0 }
        return -side * (1 - timeToWall / window) * 0.34 * reach
    }

    private func updateNode(_ frame: PathSample, dt: Float) {
        bob += dt
        let hover = Self.hoverHeight + 0.06 * sin(bob * 3.1)
        worldPosition = frame.position + frame.right * d + frame.up * hover
        let forward = simd_normalize(frame.forward * cos(heading) + frame.right * sin(heading))
        let right = simd_normalize(simd_cross(forward, frame.up))
        let up = simd_cross(right, forward)
        worldForward = simd_normalize(frame.forward * cos(travel) + frame.right * sin(travel))
        node.simdPosition = worldPosition
        node.simdOrientation = simd_quatf(simd_float3x3(columns: (right, up, -forward)))

        // Lean into the turn and with the slide; nose lifts a touch on boost.
        let roll = max(-0.6, min(0.6, -yawRate * 0.26 - (heading - travel) * 0.5))
        let pitch: Float = boost > 0 ? 0.035 : 0
        let target = simd_quatf(angle: roll, axis: SIMD3(0, 0, 1)) * simd_quatf(angle: pitch, axis: SIMD3(1, 0, 0))
        body.simdOrientation = dt > 0 ? simd_slerp(body.simdOrientation, target, min(1, 10 * dt)) : target
        let thrust = speed / design.spec.topSpeed
        ShipMesh.setThrust(boost > 0 ? 1.7 : 0.25 + 0.75 * thrust, on: body)
    }
}

/// The rival pilot. It flies the same ship model as the player through `ShipInput`:
/// aims at a point ahead on its lane, and airbrakes for corners it cannot make flat.
enum RivalDriver {
    static func input(for ship: Ship, track: TrackPath) -> ShipInput {
        let spec = ship.design.spec
        let look = 9 + ship.speed * 0.32
        let ahead = track.frame(at: ship.s + look)
        let limit = ahead.halfWidth - Ship.halfWidth - 0.8
        // Drift towards the inside of whatever is coming.
        let apex = track.frame(at: ship.s + look * 2.2).curvature
        let targetD = max(-limit, min(limit, ship.lane + ship.avoid + max(-4, min(4, apex * 420))))
        let aim = atan2(targetD - ship.d, look)
        let feedForward = track.frame(at: ship.s + ship.speed * 0.12).curvature * ship.speed
        let reach = max(0.2, ship.authority(brake: 0))
        let steer = ((aim - ship.heading) * 2.6 + feedForward) / reach

        // Airbrake when a corner inside braking distance needs less speed than we have.
        var brake: Float = 0
        let cornerYaw = spec.agility * 0.72
        let scan = 20 + ship.speed * ship.speed / 40
        var distance: Float = 0
        while distance < scan {
            let k = abs(track.frame(at: ship.s + distance).curvature)
            if k > 1e-4 {
                let cornerSpeed = cornerYaw / k
                let allowed = (cornerSpeed * cornerSpeed + 2 * 24 * distance).squareRoot()
                if ship.speed > allowed { brake = 0.8; break }
            }
            distance += 8
        }
        return ShipInput(steer: max(-1, min(1, steer)), brake: brake)
    }
}
