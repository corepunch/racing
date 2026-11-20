import Foundation
import simd

/// What a car can do. Everything the physics needs, plus 0...1 ratings for the menu bars.
struct CarSpec {
    /// Flat-out speed in m/s.
    var topSpeed: Float
    /// Drive acceleration from rest in m/s².
    var thrust: Float
    /// Front-wheel lock at a standstill, in radians.
    var steeringLock: Float
    /// Tyre grip (the wheels' friction slip).
    var grip: Float
    /// 0...1: how slippery the bodywork is against barriers. Armoured cars glance off and keep their speed.
    var armor: Float

    /// Menu ratings in the order of `CarSpec.statNames`.
    var ratings: [Float]
    static let statNames = ["SPEED", "THRUST", "AGILITY", "ARMOR"]

    init(ratings r: [Float]) {
        ratings = r
        topSpeed = 84 + 20 * r[0]
        thrust = 15 + 8 * r[1]
        steeringLock = 0.46 + 0.16 * r[2]
        grip = 4.8 + 1.5 * r[2]
        armor = r[3]
    }
}

/// A complete car: its numbers and the shape parameters the mesh is built from.
/// Everything comes from the seed; form follows function, so a fast car is long
/// and low, a strong one has fat rear tyres and more exhausts, an agile one has
/// a wide track and big wings, an armoured one is bulky.
struct CarDesign {
    enum Layout: Int, CaseIterable {
        /// Narrow central tub with side pods: an open-wheel single-seater.
        case formula
        /// Wide wedge that fills the space between the wheels.
        case wedge
        /// Twin booms either side of a central pod.
        case twin
    }

    let seed: UInt64
    var name: String
    let className: String
    /// Who built it: lettered on the bodywork, with the race number.
    let maker: String
    let number: Int
    var spec: CarSpec
    let garage: GarageBuild?
    private let garageDimensions: GarageDimensions?

    let layout: Layout
    let length: Float
    /// Half-width of the bodywork.
    let width: Float
    let height: Float
    /// Lateral distance from the centre line to the middle of each wheel.
    let track: Float
    let frontRadius: Float
    let rearRadius: Float
    let tyreWidth: Float
    /// 0...1 size of the front and rear wings.
    let wing: Float
    let engineCount: Int
    let engineRadius: Float

    let primary: SIMD3<Float>
    let accent: SIMD3<Float>
    let glow: SIMD3<Float>

    /// Overall half-width including the tyres.
    var halfWidth: Float { max(track + tyreWidth / 2, garageDimensions?.bodyHalfWidth ?? 0) }
    var axle: Float { garageDimensions?.axle ?? length * 0.31 }
    var frontCollisionExtent: Float { garageDimensions?.frontExtent ?? length * 0.46 }
    var rearCollisionExtent: Float { garageDimensions?.rearExtent ?? length * 0.46 }

    init(garage: GarageBuild) {
        let dimensions = GarageDimensions(garage)
        self.garage = garage
        garageDimensions = dimensions
        seed = 0
        name = "MY RACER"
        maker = (garage.part(at: .frame)?.title ?? "Sprint").uppercased()
        className = maker + " FRAME"
        // A number that belongs to the build: the same parts always carry the same one.
        let parts = CarSlot.allCases.compactMap { garage.part(at: $0)?.rawValue }.joined()
        number = 2 + parts.utf8.reduce(0) { ($0 &* 31 &+ Int($1)) % 98 }
        spec = dimensions.spec
        layout = .wedge
        length = dimensions.frontExtent + dimensions.rearExtent
        width = dimensions.bodyWidth
        height = dimensions.deckHeight
        track = dimensions.track
        frontRadius = dimensions.frontRadius
        rearRadius = dimensions.rearRadius
        tyreWidth = dimensions.tyreWidth
        wing = 0
        engineCount = 1
        engineRadius = 0.20
        primary = garage.paint(for: .frame).rgb
        accent = garage.paint(for: .front).rgb
        glow = SIMD3(0.28, 0.90, 1)
    }

    /// `focus` picks the stat the car leans on, so a roster covers every style.
    init(seed: UInt64, focus: Int, hue: Float, budget: Float = 2.3) {
        self.seed = seed
        garage = nil
        garageDimensions = nil
        var rng = SplitMix64(seed: seed &* 0x9E3779B97F4A7C15 &+ 0xD1B54A32)

        // Stats: random, pulled towards the focus, then scaled to a common budget.
        var raw = (0..<4).map { _ in rng.float(0.25...0.75) }
        raw[focus % 4] += rng.float(0.45...0.6)
        raw[(focus + 1 + Int.random(in: 0...2, using: &rng)) % 4] -= 0.12
        let sum = raw.reduce(0, +)
        var ratings = raw.map { max(0.12, min(1, $0 * budget / sum)) }
        // Whatever clipping lost goes back to the weakest stat.
        let lost = budget - ratings.reduce(0, +)
        if lost > 0, let weakest = ratings.indices.min(by: { ratings[$0] < ratings[$1] }) {
            ratings[weakest] = min(1, ratings[weakest] + lost)
        }
        spec = CarSpec(ratings: ratings)
        let (speed, thrust, agility, armor) = (ratings[0], ratings[1], ratings[2], ratings[3])

        layout = Layout.allCases[Int.random(in: 0..<Layout.allCases.count, using: &rng)]
        length = 4.2 + 1.3 * speed + rng.float(-0.1...0.1)
        track = 1.12 + 0.26 * agility + rng.float(-0.03...0.03)
        tyreWidth = 0.44 + 0.2 * thrust
        frontRadius = 0.37 + 0.06 * armor
        rearRadius = 0.44 + 0.13 * thrust
        // Bodywork stays clear of the tyres.
        width = min(track - tyreWidth / 2 - 0.12, 0.5 + 0.4 * armor + rng.float(-0.03...0.03))
        height = 0.74 + 0.2 * armor - 0.1 * speed + rng.float(-0.02...0.04)
        wing = 0.25 + 0.75 * agility
        engineCount = thrust > 0.7 ? 3 : (thrust > 0.38 ? 2 : 1)
        engineRadius = 0.15 + 0.1 * thrust + (engineCount == 1 ? 0.08 : 0)

        primary = Self.hsv(hue, rng.float(0.72...0.92), rng.float(0.85...1))
        let accentHue = hue + (rng.float() < 0.5 ? 0.5 : 0.08) + rng.float(-0.04...0.04)
        accent = rng.float() < 0.4 ? SIMD3(0.92, 0.94, 0.98) : Self.hsv(accentHue, 0.7, 1)
        glow = Self.hsv(hue + rng.float(0.42...0.58), 0.75, 1)

        // A maker for each character and a model from that maker's range.
        let strongest = ratings.indices.max(by: { ratings[$0] < ratings[$1] }) ?? 0
        className = ["INTERCEPTOR", "DRAGSTER", "SLIDER", "BRUISER"][strongest]
        let range = Self.models[strongest]
        maker = Self.makers[strongest]
        name = "\(maker) \(range[Int.random(in: 0..<range.count, using: &rng)])"
        number = Int.random(in: 2...99, using: &rng)
    }

    /// Who builds each class of car, in the order of `CarSpec.statNames`.
    private static let makers = ["VANTA", "KORR", "LYRA", "BRUNT"]
    private static let models = [
        ["COMET", "JAVELIN", "MERIDIAN", "ZEPHYR", "MISTRAL", "TRACER", "AURORA", "PHOTON"],
        ["SURGE", "RAMJET", "TORQUE", "FURNACE", "STAMPEDE", "DYNAMO", "HOWL", "PISTON"],
        ["KITE", "DART", "WISP", "SWALLOW", "HAIRPIN", "RIBBON", "MANTIS", "FERRET"],
        ["BULWARK", "RAMPART", "MASTIFF", "IRONSIDE", "CITADEL", "BOULDER", "RHINO", "GRANITE"],
    ]

    private static func hsv(_ h: Float, _ s: Float, _ v: Float) -> SIMD3<Float> {
        let hue = (h - h.rounded(.down)) * 6
        let i = Int(hue), f = hue - Float(i)
        let p = v * (1 - s), q = v * (1 - s * f), t = v * (1 - s * (1 - f))
        switch i % 6 {
        case 0: return SIMD3(v, t, p)
        case 1: return SIMD3(q, v, p)
        case 2: return SIMD3(p, v, t)
        case 3: return SIMD3(p, q, v)
        case 4: return SIMD3(t, p, v)
        default: return SIMD3(v, p, q)
        }
    }
}

enum CarRoster {
    /// Six cars: one specialist per stat and two wildcards, hues spread round the wheel.
    static let all: [CarDesign] = (0..<6).map { i in
        CarDesign(seed: UInt64(101 + i * 37), focus: i, hue: Float(i) * 0.618 + 0.52)
    }
}
