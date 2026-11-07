import SceneKit
import simd

// Surface type controls Sega Rally style grip and drift thresholds
enum SurfaceType: Int, CaseIterable {
    case tarmac
    case dirt
    case gravel

    // N/rad — higher = sharper cornering response
    var corneringStiffness: Float {
        switch self {
        case .tarmac:  return 15_000
        case .dirt:    return  8_000
        case .gravel:  return  6_200
        }
    }

    // Slip angle (rad) beyond which rear wheels lose grip and drift begins
    var driftThreshold: Float {
        switch self {
        case .tarmac:  return 0.45
        case .dirt:    return 0.26
        case .gravel:  return 0.20
        }
    }

    var name: String {
        switch self {
        case .tarmac:  return "TARMAC"
        case .dirt:    return "DIRT"
        case .gravel:  return "GRAVEL"
        }
    }

    var color: UIColor {
        switch self {
        case .tarmac:  return UIColor(white: 0.28, alpha: 1)
        case .dirt:    return UIColor(red: 0.52, green: 0.36, blue: 0.20, alpha: 1)
        case .gravel:  return UIColor(white: 0.60, alpha: 1)
        }
    }
}

struct PathSample {
    var position: SIMD3<Float>
    var forward: SIMD3<Float>    // normalised, tangent to curve
    var right: SIMD3<Float>      // normalised, perpendicular to forward in XZ plane
    var up: SIMD3<Float>         // normalised, may be banked
    var arcLength: Float         // cumulative distance from sample[0]
    var surface: SurfaceType
    var halfWidth: Float         // road half-width in metres
}

final class TrackPath {

    // Closed loop Catmull-Rom control points.
    // Roughly 350 × 300 m oval with chicanes — ~1 100 m lap at ~50 m/s average gives ~22 s.
    static let controlPoints: [SIMD3<Float>] = [
        SIMD3<Float>(   0,  0, -175),
        SIMD3<Float>(  90,  0, -155),
        SIMD3<Float>( 165,  0,  -95),
        SIMD3<Float>( 185,  0,    0),
        SIMD3<Float>( 165,  0,   95),
        SIMD3<Float>(  90,  0,  155),
        SIMD3<Float>(   0,  0,  175),
        SIMD3<Float>( -75,  0,  155),
        SIMD3<Float>(-160,  0,   75),
        SIMD3<Float>(-200,  0,  -20),
        SIMD3<Float>(-160,  0, -105),
        SIMD3<Float>( -75,  0, -155),
    ]

    let samples: [PathSample]
    let totalLength: Float
    let stepCount: Int

    // 2-D bounds (XZ plane) for minimap projection
    let boundsMin: SIMD2<Float>
    let boundsMax: SIMD2<Float>

    init(stepCount: Int = 512) {
        self.stepCount = stepCount

        var built = [PathSample]()
        built.reserveCapacity(stepCount)

        var cumDist: Float = 0
        let pts = Self.controlPoints
        let n = pts.count

        for i in 0..<stepCount {
            let t     = Float(i) / Float(stepCount) * Float(n)
            let seg   = Int(t) % n
            let u     = t - floor(t)
            let p0    = pts[(seg - 1 + n) % n]
            let p1    = pts[seg]
            let p2    = pts[(seg + 1) % n]
            let p3    = pts[(seg + 2) % n]

            let pos   = catmullRom(p0, p1, p2, p3, u)
            var tan   = catmullRomTangent(p0, p1, p2, p3, u)
            if simd_length(tan) < 1e-6 { tan = SIMD3<Float>(0, 0, 1) }
            let fwd   = simd_normalize(tan)
            let worldUp = SIMD3<Float>(0, 1, 0)
            let right = simd_normalize(simd_cross(fwd, worldUp))
            let up    = simd_normalize(simd_cross(right, fwd))

            if !built.isEmpty {
                cumDist += simd_length(pos - built.last!.position)
            }

            let progress = Float(i) / Float(stepCount)
            let surface: SurfaceType
            switch progress {
            case 0.00..<0.28: surface = .tarmac
            case 0.28..<0.52: surface = .dirt
            case 0.52..<0.68: surface = .gravel
            case 0.68..<0.84: surface = .dirt
            default:           surface = .tarmac
            }

            built.append(PathSample(
                position: pos,
                forward: fwd,
                right: right,
                up: up,
                arcLength: cumDist,
                surface: surface,
                halfWidth: 5.5
            ))
        }

        samples = built
        // Close the loop distance
        totalLength = cumDist + (built.count > 1 ? simd_length(built.last!.position - built.first!.position) : 0)

        // Compute XZ bounds for minimap
        var minX = Float.greatestFiniteMagnitude, minZ = Float.greatestFiniteMagnitude
        var maxX = -Float.greatestFiniteMagnitude, maxZ = -Float.greatestFiniteMagnitude
        for s in built {
            minX = min(minX, s.position.x); maxX = max(maxX, s.position.x)
            minZ = min(minZ, s.position.z); maxZ = max(maxZ, s.position.z)
        }
        boundsMin = SIMD2<Float>(minX - 20, minZ - 20)
        boundsMax = SIMD2<Float>(maxX + 20, maxZ + 20)
    }

    // Returns index of sample nearest to world position (XZ distance).
    func closestSampleIndex(to world: SIMD3<Float>) -> Int {
        var bestIdx = 0
        var bestDist = Float.greatestFiniteMagnitude
        for (i, s) in samples.enumerated() {
            let d = simd_length_squared(SIMD2<Float>(world.x - s.position.x, world.z - s.position.z))
            if d < bestDist { bestDist = d; bestIdx = i }
        }
        return bestIdx
    }

    func sample(at index: Int) -> PathSample {
        return samples[((index % stepCount) + stepCount) % stepCount]
    }

    // Projects a world XZ position to normalised [0,1] minimap coordinates.
    func minimapPosition(for world: SIMD3<Float>) -> SIMD2<Float> {
        let range = boundsMax - boundsMin
        return SIMD2<Float>(
            (world.x - boundsMin.x) / range.x,
            (world.z - boundsMin.y) / range.y
        )
    }
}

// MARK: - Catmull-Rom

private func catmullRom(
    _ p0: SIMD3<Float>, _ p1: SIMD3<Float>,
    _ p2: SIMD3<Float>, _ p3: SIMD3<Float>, _ t: Float
) -> SIMD3<Float> {
    let t2 = t * t, t3 = t2 * t
    return 0.5 * (
        (2 * p1) +
        (-p0 + p2) * t +
        (2*p0 - 5*p1 + 4*p2 - p3) * t2 +
        (-p0 + 3*p1 - 3*p2 + p3) * t3
    )
}

private func catmullRomTangent(
    _ p0: SIMD3<Float>, _ p1: SIMD3<Float>,
    _ p2: SIMD3<Float>, _ p3: SIMD3<Float>, _ t: Float
) -> SIMD3<Float> {
    let t2 = t * t
    return 0.5 * (
        (-p0 + p2) +
        2 * (2*p0 - 5*p1 + 4*p2 - p3) * t +
        3 * (-p0 + 3*p1 - 3*p2 + p3) * t2
    )
}
