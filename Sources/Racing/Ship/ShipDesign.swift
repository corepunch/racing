import Foundation
import simd

/// What a ship can do. Everything the dynamics need, plus 0...1 ratings for the menu bars.
struct ShipSpec {
    /// Flat-out speed in m/s.
    var topSpeed: Float
    /// Acceleration from rest in m/s².
    var thrust: Float
    /// Yaw rate at full lock in rad/s.
    var agility: Float
    /// How quickly the direction of travel follows the nose, 1/s. Lower slides more.
    var grip: Float
    /// Share of a wall hit's speed loss the hull absorbs, 0...1.
    var shield: Float

    /// Menu ratings in the order of `ShipSpec.statNames`.
    var ratings: [Float]
    static let statNames = ["SPEED", "THRUST", "AGILITY", "SHIELD"]

    init(ratings r: [Float]) {
        ratings = r
        topSpeed = 80 + 18 * r[0]
        thrust = 17 + 15 * r[1]
        agility = 1.30 + 0.60 * r[2]
        grip = 3.6 + 2.2 * r[2]
        shield = r[3]
    }
}

/// A complete ship: its numbers and the shape parameters the mesh is built from.
/// Everything comes from the seed; form follows function, so a fast ship is long
/// and slim, a strong one has big engines, an agile one has wide wings.
struct ShipDesign {
    enum Layout: Int, CaseIterable {
        /// One slim fuselage with swept wings.
        case dart
        /// Twin prows either side of a central pod.
        case twin
        /// Wide flat body with winglets.
        case manta
    }

    let seed: UInt64
    let name: String
    let className: String
    let spec: ShipSpec

    let layout: Layout
    let length: Float
    let width: Float
    let height: Float
    let wingSpan: Float
    let wingSweep: Float
    let finCount: Int
    let finHeight: Float
    let engineCount: Int
    let engineRadius: Float
    let noseDroop: Float

    let primary: SIMD3<Float>
    let accent: SIMD3<Float>
    let glow: SIMD3<Float>

    /// `focus` picks the stat the ship leans on, so a roster covers every style.
    init(seed: UInt64, focus: Int, hue: Float) {
        self.seed = seed
        var rng = SplitMix64(seed: seed &* 0x9E3779B97F4A7C15 &+ 0xD1B54A32)

        // Stats: random, pulled towards the focus, then scaled to a common budget.
        var raw = (0..<4).map { _ in rng.float(0.25...0.75) }
        raw[focus % 4] += rng.float(0.45...0.6)
        raw[(focus + 1 + Int.random(in: 0...2, using: &rng)) % 4] -= 0.12
        let budget: Float = 2.3
        let sum = raw.reduce(0, +)
        var ratings = raw.map { max(0.12, min(1, $0 * budget / sum)) }
        // Whatever clipping lost goes back to the weakest stat.
        let lost = budget - ratings.reduce(0, +)
        if lost > 0, let weakest = ratings.indices.min(by: { ratings[$0] < ratings[$1] }) {
            ratings[weakest] = min(1, ratings[weakest] + lost)
        }
        spec = ShipSpec(ratings: ratings)
        let (speed, thrust, agility, shield) = (ratings[0], ratings[1], ratings[2], ratings[3])

        layout = Layout.allCases[Int.random(in: 0..<Layout.allCases.count, using: &rng)]
        length = 4.3 + 1.7 * speed + rng.float(-0.15...0.15)
        width = 0.62 + 0.42 * shield + rng.float(-0.04...0.04)
        height = 0.42 + 0.22 * shield + rng.float(-0.03...0.05)
        wingSpan = 0.55 + 1.25 * agility + rng.float(-0.1...0.1)
        wingSweep = rng.float(0.25...0.9)
        finCount = agility > 0.62 ? 2 : (rng.float() < 0.75 ? 1 : 0)
        finHeight = rng.float(0.45...0.85)
        engineCount = thrust > 0.7 ? 3 : (thrust > 0.38 ? 2 : 1)
        engineRadius = 0.2 + 0.16 * thrust + (engineCount == 1 ? 0.1 : 0)
        noseDroop = rng.float(0...0.14)

        primary = Self.hsv(hue, rng.float(0.72...0.92), rng.float(0.85...1))
        let accentHue = hue + (rng.float() < 0.5 ? 0.5 : 0.08) + rng.float(-0.04...0.04)
        accent = rng.float() < 0.35 ? SIMD3(0.92, 0.94, 0.98) : Self.hsv(accentHue, 0.7, 1)
        glow = Self.hsv(hue + rng.float(0.42...0.58), 0.75, 1)

        let syllables = ["VA", "KY", "ZE", "RO", "XI", "TA", "NU", "OR", "EL", "SA", "QUA", "MI", "DRA", "VEX", "LU", "ON"]
        var word = ""
        for _ in 0..<Int.random(in: 2...3, using: &rng) { word += syllables[Int.random(in: 0..<syllables.count, using: &rng)] }
        name = "\(word)-\(Int.random(in: 2...99, using: &rng))"
        let strongest = ratings.indices.max(by: { ratings[$0] < ratings[$1] }) ?? 0
        className = ["INTERCEPTOR", "DRAGSTER", "SLIDER", "BRUISER"][strongest]
    }

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

enum ShipRoster {
    /// Six ships: one specialist per stat and two wildcards, hues spread round the wheel.
    static let all: [ShipDesign] = (0..<6).map { i in
        ShipDesign(seed: UInt64(101 + i * 37), focus: i, hue: Float(i) * 0.618 + 0.52)
    }
}
