import UIKit
import simd

/// One distortion of the master curve. The curve starts as a flat circle of control
/// points; radial deformers (`lobes`, `pinch`) and `hills` are evaluated per point,
/// then the cartesian ones (`stretch`, `shear`, `warp`) are applied in list order.
enum CurveDeformer {
    /// Sinusoidal radius modulation: `count` bulges, `amount` as a fraction of the radius.
    case lobes(count: Int, amount: Float, phase: Float)
    /// Pulls the ring towards the centre around `angle` (radians), making a tight inward bend.
    case pinch(angle: Float, amount: Float, width: Float)
    /// Height wave in metres, `count` crests per lap.
    case hills(count: Int, height: Float, phase: Float)
    case stretch(x: Float, z: Float)
    case shear(Float)
    /// Smooth noise displacement in metres; `scale` is the feature size.
    case warp(amount: Float, scale: Float, seed: UInt64)
}

/// The closed master curve everything is built from: the road is swept along it and
/// the city, pylons and gates are placed in its (distance, lateral, height) frame.
struct TrackCurve {
    var radius: Float = 330
    var pointCount = 24
    var altitude: Float = 0
    var deformers: [CurveDeformer]

    func controlPoints() -> [SIMD3<Float>] {
        var points = (0..<pointCount).map { i -> SIMD3<Float> in
            let a = Float(i) / Float(pointCount) * 2 * .pi
            var r = radius
            var y = altitude
            for deformer in deformers {
                switch deformer {
                case let .lobes(count, amount, phase):
                    r += radius * amount * sin(Float(count) * a + phase)
                case let .pinch(angle, amount, width):
                    let d = remainder(a - angle, 2 * .pi)
                    r -= radius * amount * exp(-(d * d) / (2 * width * width))
                case let .hills(count, height, phase):
                    y += height * sin(Float(count) * a + phase)
                case .stretch, .shear, .warp:
                    break
                }
            }
            return SIMD3(cos(a) * r, y, sin(a) * r)
        }
        for deformer in deformers {
            switch deformer {
            case let .stretch(x, z):
                points = points.map { SIMD3($0.x * x, $0.y, $0.z * z) }
            case let .shear(k):
                points = points.map { SIMD3($0.x + $0.z * k, $0.y, $0.z) }
            case let .warp(amount, scale, seed):
                let noise = Noise2D(seed: seed)
                points = points.map { p in
                    let dx = noise.fbm(p.x / scale, p.z / scale, octaves: 2)
                    let dz = noise.fbm(p.x / scale + 37.3, p.z / scale - 11.9, octaves: 2)
                    return SIMD3(p.x + dx * amount * 2, p.y, p.z + dz * amount * 2)
                }
            case .lobes, .pinch, .hills:
                break
            }
        }
        return points
    }

    /// A random but drivable loop: a few lobes, maybe a pinch, rolling height.
    static func random(seed: UInt64) -> TrackCurve {
        var rng = SplitMix64(seed: seed &* 7919 &+ 13)
        var deformers: [CurveDeformer] = []
        var counts = [2, 3, 4, 5].shuffled(using: &rng)
        let amounts: [ClosedRange<Float>] = [0.12...0.22, 0.06...0.13, 0.03...0.07]
        for range in amounts {
            deformers.append(.lobes(count: counts.removeLast(), amount: rng.float(range),
                                    phase: rng.float(0...(2 * .pi))))
        }
        for _ in 0..<Int.random(in: 0...2, using: &rng) {
            deformers.append(.pinch(angle: rng.float(0...(2 * .pi)), amount: rng.float(0.14...0.26),
                                    width: rng.float(0.18...0.3)))
        }
        deformers.append(.hills(count: 1, height: rng.float(14...26), phase: rng.float(0...(2 * .pi))))
        deformers.append(.hills(count: 2, height: rng.float(7...14), phase: rng.float(0...(2 * .pi))))
        deformers.append(.hills(count: Int.random(in: 3...4, using: &rng), height: rng.float(3...8),
                                phase: rng.float(0...(2 * .pi))))
        deformers.append(.stretch(x: rng.float(0.85...1.3), z: rng.float(0.85...1.3)))
        deformers.append(.shear(rng.float(-0.25...0.25)))
        deformers.append(.warp(amount: rng.float(8...18), scale: 260, seed: seed &+ 101))
        return TrackCurve(radius: rng.float(300...360), deformers: deformers)
    }
}

/// Colours that drive every generated texture, the sky and the lighting.
struct TrackTheme {
    var skyZenith: SIMD3<Float>
    var skyHorizon: SIMD3<Float>
    var skyGlow: SIMD3<Float>
    var stars: Float
    var fogStart: CGFloat = 140
    var fogEnd: CGFloat = 1100
    /// Primary and secondary emissive colours.
    var neonA: SIMD3<Float>
    var neonB: SIMD3<Float>
    /// Painted markings (arrows, edge lines, hazard stripes).
    var paint: SIMD3<Float>
    /// Road deck metal and the darker structural hull.
    var metal: SIMD3<Float>
    var hull: SIMD3<Float>
    var window: SIMD3<Float>
    var sunColor: SIMD3<Float>
    var sunIntensity: CGFloat
    var sunAngles: SIMD2<Float>
    var ambient: CGFloat
    var environment: CGFloat

    static let neonNight = TrackTheme(
        skyZenith: SIMD3(0.015, 0.02, 0.07), skyHorizon: SIMD3(0.17, 0.07, 0.26),
        skyGlow: SIMD3(0.95, 0.25, 0.60), stars: 1,
        neonA: SIMD3(0.10, 0.90, 1.00), neonB: SIMD3(1.00, 0.15, 0.60),
        paint: SIMD3(0.95, 0.76, 0.12), metal: SIMD3(0.62, 0.66, 0.74), hull: SIMD3(0.20, 0.22, 0.28),
        window: SIMD3(1.00, 0.80, 0.50),
        sunColor: SIMD3(0.62, 0.70, 1.00), sunIntensity: 700, sunAngles: SIMD2(-.pi / 3.2, .pi / 5),
        ambient: 140, environment: 1.6)

    static let ember = TrackTheme(
        skyZenith: SIMD3(0.10, 0.09, 0.26), skyHorizon: SIMD3(0.78, 0.36, 0.20),
        skyGlow: SIMD3(1.00, 0.62, 0.18), stars: 0.3,
        neonA: SIMD3(1.00, 0.50, 0.08), neonB: SIMD3(0.10, 0.92, 0.78),
        paint: SIMD3(0.93, 0.93, 0.90), metal: SIMD3(0.72, 0.64, 0.57), hull: SIMD3(0.26, 0.21, 0.20),
        window: SIMD3(1.00, 0.70, 0.35),
        sunColor: SIMD3(1.00, 0.66, 0.40), sunIntensity: 1100, sunAngles: SIMD2(-.pi / 9, -.pi / 3),
        ambient: 220, environment: 1.3)

    static let cryo = TrackTheme(
        skyZenith: SIMD3(0.20, 0.42, 0.74), skyHorizon: SIMD3(0.74, 0.84, 0.93),
        skyGlow: SIMD3(1.00, 0.97, 0.90), stars: 0,
        fogStart: 220, fogEnd: 1300,
        neonA: SIMD3(0.15, 0.55, 1.00), neonB: SIMD3(1.00, 0.30, 0.08),
        paint: SIMD3(0.95, 0.33, 0.10), metal: SIMD3(0.82, 0.84, 0.88), hull: SIMD3(0.46, 0.50, 0.56),
        window: SIMD3(0.75, 0.90, 1.00),
        sunColor: SIMD3(1.00, 0.97, 0.92), sunIntensity: 1500, sunAngles: SIMD2(-.pi / 3.5, .pi / 6),
        ambient: 420, environment: 1.1)

    static let acid = TrackTheme(
        skyZenith: SIMD3(0.01, 0.05, 0.05), skyHorizon: SIMD3(0.10, 0.26, 0.15),
        skyGlow: SIMD3(0.55, 1.00, 0.25), stars: 0.6,
        neonA: SIMD3(0.60, 1.00, 0.10), neonB: SIMD3(0.62, 0.25, 1.00),
        paint: SIMD3(0.92, 0.92, 0.25), metal: SIMD3(0.58, 0.66, 0.62), hull: SIMD3(0.16, 0.22, 0.20),
        window: SIMD3(0.70, 1.00, 0.60),
        sunColor: SIMD3(0.70, 1.00, 0.80), sunIntensity: 650, sunAngles: SIMD2(-.pi / 3, -.pi / 4),
        ambient: 150, environment: 1.6)

    static let all: [TrackTheme] = [.neonNight, .ember, .cryo, .acid]
}

/// Everything about a circuit derives from this: the curve, the seed for textures
/// and city placement, and the theme.
struct TrackDefinition {
    var name: String
    var seed: UInt64
    var curve: TrackCurve
    var theme: TrackTheme
    /// Deck half-width in metres, and how far it swells and narrows along the lap.
    var halfWidth: Float = 8
    var widthVariation: Float = 1.5
    var banking: Float = 1
}

enum TrackLibrary {
    static let all: [TrackDefinition] = [
        // Hand-tuned: three lobes with one hard inward bend and a long descent.
        TrackDefinition(
            name: "Neon Meridian", seed: 11,
            curve: TrackCurve(radius: 330, deformers: [
                .lobes(count: 3, amount: 0.17, phase: 0.4),
                .lobes(count: 5, amount: 0.06, phase: 2.1),
                .pinch(angle: 3.9, amount: 0.24, width: 0.24),
                .hills(count: 1, height: 22, phase: 1.0),
                .hills(count: 3, height: 7, phase: 0.3),
                .stretch(x: 1.25, z: 0.9),
                .warp(amount: 12, scale: 260, seed: 5),
            ]),
            theme: .neonNight),
        TrackDefinition(name: "Ember Skyway", seed: 23, curve: .random(seed: 23), theme: .ember),
        TrackDefinition(name: "Cryo Loop", seed: 37, curve: .random(seed: 37), theme: .cryo,
                        halfWidth: 9, widthVariation: 2),
        TrackDefinition(name: "Acid Spire", seed: 53, curve: .random(seed: 53), theme: .acid,
                        banking: 1.3),
    ]

    /// Any seed gives a complete circuit: curve, city and textures.
    static func generated(seed: UInt64) -> TrackDefinition {
        TrackDefinition(name: "Sector \(seed)", seed: seed, curve: .random(seed: seed),
                        theme: TrackTheme.all[Int(seed % UInt64(TrackTheme.all.count))])
    }
}
