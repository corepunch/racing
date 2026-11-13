import UIKit
import simd

/// Data-driven description of a circuit; everything else (road, terrain,
/// textures, scenery) is generated from it.
struct TrackDefinition {

    struct Zone {
        enum Kind { case tunnel, town }
        var kind: Kind
        /// Lap fractions in [0, 1).
        var start: Float
        var end: Float
        /// Tunnels: extra mountain height above the tunnel roof.
        var hill: Float = 0
    }

    struct SurfaceRange {
        var start: Float
        var end: Float
        var surface: SurfaceType
    }

    enum WaterBody {
        /// Sea on the side `direction` points to, shoreline at dot(xz, direction) == offset.
        case coast(direction: SIMD2<Float>, offset: Float)
        case lake(center: SIMD2<Float>, radius: Float)
    }

    enum RoofStyle { case gabled, flat, mixed }

    /// Selects tree sprites and the forest-wall texture baked by Tools/bake_tree_sprites.swift.
    enum ForestBiome: String { case alpine, temperate, coastal, arid }

    struct Palette {
        var grassA: SIMD3<Float>
        var grassB: SIMD3<Float>
        var rockA: SIMD3<Float>
        var rockB: SIMD3<Float>
        var sand: SIMD3<Float>
        var facades: [SIMD3<Float>]
        var roof: SIMD3<Float>
    }

    struct Environment {
        var seed: UInt64
        var baseHeight: Float
        var hillAmplitude: Float
        var hillScale: Float
        var mountainAmplitude: Float
        var waterLevel: Float?
        var water: [WaterBody] = []
        var palette: Palette
        var treeDensity: Float
        var forest: ForestBiome
        var roofStyle: RoofStyle
        /// Slope (0 = flat, 1 = vertical) where grass gives way to rock.
        var rockSlope: Float = 0.55
        var fogColor: UIColor
        var fogStart: CGFloat = 90
        var fogEnd: CGFloat = 520
        var sunAngles: SIMD2<Float> = SIMD2(-.pi / 4.5, .pi / 6)
    }

    var name: String
    var controlPoints: [SIMD3<Float>]
    var halfWidth: Float = 5.5
    var banking: Float = 1
    var surfaces: [SurfaceRange] = []
    var zones: [Zone] = []
    var environment: Environment
}

// MARK: - Library

enum TrackLibrary {
    typealias Zone = TrackDefinition.Zone
    typealias SurfaceRange = TrackDefinition.SurfaceRange
    typealias Environment = TrackDefinition.Environment
    typealias Palette = TrackDefinition.Palette

    static let all: [TrackDefinition] = [alpinePass, coastalHighway, oldTown, canyonLakes]

    static let alpinePass = TrackDefinition(
        name: "Alpine Pass",
        controlPoints: [
            SIMD3(   0, 10, -300), SIMD3( 170, 14, -300), SIMD3( 290, 21, -240),
            SIMD3( 240, 25, -145), SIMD3( 350, 30,  -60), SIMD3( 380, 34,   60),
            SIMD3( 290, 30,  145), SIMD3( 220, 27,  110), SIMD3( 155, 22,  205),
            SIMD3(  30, 17,  285), SIMD3(-100, 12,  260), SIMD3(-150, 10,  165),
            SIMD3(-260,  9,  180), SIMD3(-350,  7,   90), SIMD3(-300,  8,    0),
            SIMD3(-365,  8, -110), SIMD3(-300,  9, -230), SIMD3(-160,  9, -285),
        ],
        banking: 1,
        surfaces: [SurfaceRange(start: 0.44, end: 0.54, surface: .gravel)],
        zones: [
            Zone(kind: .tunnel, start: 0.25, end: 0.36, hill: 34),
            Zone(kind: .town, start: 0.62, end: 0.76),
        ],
        environment: Environment(
            seed: 11, baseHeight: 14, hillAmplitude: 22, hillScale: 230,
            mountainAmplitude: 150, waterLevel: 2,
            water: [.lake(center: SIMD2(40, 0), radius: 120)],
            palette: Palette(
                grassA: SIMD3(0.22, 0.38, 0.16), grassB: SIMD3(0.36, 0.48, 0.20),
                rockA: SIMD3(0.42, 0.41, 0.40), rockB: SIMD3(0.62, 0.60, 0.57),
                sand: SIMD3(0.55, 0.52, 0.44),
                facades: [SIMD3(0.92, 0.88, 0.78), SIMD3(0.85, 0.80, 0.70), SIMD3(0.95, 0.94, 0.90),
                          SIMD3(0.72, 0.56, 0.40)],
                roof: SIMD3(0.36, 0.22, 0.16)),
            treeDensity: 1.0, forest: .alpine, roofStyle: .gabled, rockSlope: 0.5,
            fogColor: UIColor(red: 0.66, green: 0.74, blue: 0.78, alpha: 1)))

    static let coastalHighway = TrackDefinition(
        name: "Coastal Highway",
        controlPoints: [
            SIMD3(-200, 14, -350), SIMD3( -20, 10, -400), SIMD3( 140,  8, -365),
            SIMD3( 205,  6, -240), SIMD3( 195,  6,  -90), SIMD3( 225,  8,   60),
            SIMD3( 195,  7,  200), SIMD3( 140,  5,  330), SIMD3(   0,  6,  395),
            SIMD3(-150, 12,  360), SIMD3(-235, 18,  220), SIMD3(-265, 22,   50),
            SIMD3(-240, 20, -120), SIMD3(-265, 16, -260),
        ],
        halfWidth: 5.5,
        banking: 0.7,
        zones: [
            Zone(kind: .tunnel, start: 0.37, end: 0.43, hill: 22),
            Zone(kind: .town, start: 0.53, end: 0.66),
        ],
        environment: Environment(
            seed: 23, baseHeight: 12, hillAmplitude: 14, hillScale: 200,
            mountainAmplitude: 90, waterLevel: 0,
            water: [.coast(direction: SIMD2(1, 0), offset: 228)],
            palette: Palette(
                grassA: SIMD3(0.36, 0.44, 0.20), grassB: SIMD3(0.54, 0.54, 0.28),
                rockA: SIMD3(0.55, 0.50, 0.42), rockB: SIMD3(0.74, 0.68, 0.58),
                sand: SIMD3(0.86, 0.78, 0.60),
                facades: [SIMD3(0.97, 0.96, 0.92), SIMD3(0.55, 0.75, 0.88), SIMD3(0.98, 0.86, 0.62),
                          SIMD3(0.92, 0.70, 0.62)],
                roof: SIMD3(0.70, 0.36, 0.22)),
            treeDensity: 0.45, forest: .coastal, roofStyle: .mixed, rockSlope: 0.6,
            fogColor: UIColor(red: 0.70, green: 0.79, blue: 0.84, alpha: 1),
            fogStart: 120, fogEnd: 600))

    static let oldTown = TrackDefinition(
        name: "Old Town",
        controlPoints: [
            SIMD3(   0, 5, -200), SIMD3( 120, 5, -205), SIMD3( 200, 6, -160),
            SIMD3( 215, 7,  -60), SIMD3( 265, 8,   10), SIMD3( 320, 9,   85),
            SIMD3( 300, 10, 195), SIMD3( 180, 9,  225), SIMD3(  60, 7,  180),
            SIMD3( -40, 6,  235), SIMD3(-160, 5,  215), SIMD3(-225, 5,  100),
            SIMD3(-200, 4,  -20), SIMD3(-245, 4, -120), SIMD3(-150, 5, -195),
        ],
        banking: 0.4,
        zones: [
            Zone(kind: .town, start: 0.05, end: 0.40),
            Zone(kind: .tunnel, start: 0.45, end: 0.52, hill: 6),
            Zone(kind: .town, start: 0.57, end: 0.93),
        ],
        environment: Environment(
            seed: 37, baseHeight: 6, hillAmplitude: 8, hillScale: 180,
            mountainAmplitude: 60, waterLevel: 1,
            water: [.lake(center: SIMD2(40, 10), radius: 70)],
            palette: Palette(
                grassA: SIMD3(0.24, 0.40, 0.18), grassB: SIMD3(0.36, 0.46, 0.22),
                rockA: SIMD3(0.45, 0.43, 0.40), rockB: SIMD3(0.60, 0.58, 0.54),
                sand: SIMD3(0.62, 0.58, 0.48),
                facades: [SIMD3(0.90, 0.80, 0.62), SIMD3(0.78, 0.52, 0.40), SIMD3(0.95, 0.92, 0.84),
                          SIMD3(0.70, 0.72, 0.62), SIMD3(0.86, 0.66, 0.50)],
                roof: SIMD3(0.55, 0.26, 0.18)),
            treeDensity: 0.6, forest: .temperate, roofStyle: .gabled,
            fogColor: UIColor(red: 0.68, green: 0.73, blue: 0.76, alpha: 1)))

    static let canyonLakes = TrackDefinition(
        name: "Canyon Lakes",
        controlPoints: [
            SIMD3(   0, 20, -300), SIMD3( 180, 18, -320), SIMD3( 320, 24, -240),
            SIMD3( 365, 30,  -80), SIMD3( 300, 36,   60), SIMD3( 330, 30,  200),
            SIMD3( 220, 22,  320), SIMD3(  60, 16,  300), SIMD3( -60, 13,  200),
            SIMD3(-200, 12,  245), SIMD3(-330, 14,  150), SIMD3(-350, 18,  -20),
            SIMD3(-260, 22, -160), SIMD3(-140, 22, -280),
        ],
        banking: 1.2,
        surfaces: [
            SurfaceRange(start: 0.12, end: 0.28, surface: .dirt),
            SurfaceRange(start: 0.50, end: 0.70, surface: .dirt),
            SurfaceRange(start: 0.70, end: 0.82, surface: .gravel),
        ],
        zones: [Zone(kind: .tunnel, start: 0.31, end: 0.40, hill: 40)],
        environment: Environment(
            seed: 53, baseHeight: 22, hillAmplitude: 18, hillScale: 160,
            mountainAmplitude: 170, waterLevel: 8,
            water: [.lake(center: SIMD2(20, -10), radius: 150),
                    .lake(center: SIMD2(-520, 40), radius: 120)],
            palette: Palette(
                grassA: SIMD3(0.62, 0.42, 0.26), grassB: SIMD3(0.72, 0.56, 0.34),
                rockA: SIMD3(0.62, 0.32, 0.20), rockB: SIMD3(0.82, 0.52, 0.34),
                sand: SIMD3(0.86, 0.72, 0.52),
                facades: [SIMD3(0.86, 0.66, 0.46)], roof: SIMD3(0.55, 0.30, 0.20)),
            treeDensity: 0.18, forest: .arid, roofStyle: .flat, rockSlope: 0.4,
            fogColor: UIColor(red: 0.80, green: 0.72, blue: 0.64, alpha: 1),
            fogStart: 120, fogEnd: 620,
            sunAngles: SIMD2(-.pi / 3.6, -.pi / 5)))
}

extension TrackDefinition {
    func surface(at progress: Float) -> SurfaceType {
        surfaces.first { progress >= $0.start && progress < $0.end }?.surface ?? .tarmac
    }

    func zone(at progress: Float) -> Zone? {
        zones.first { progress >= $0.start && progress < $0.end }
    }
}
