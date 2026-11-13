import SceneKit
import simd

/// Deck texture of one 16 m section. Each case is a separately generated tile.
enum DeckPattern: Int, CaseIterable {
    case plain, chevrons, turn, hazard, grate, boost, barcode, start
}

enum WallPattern: Int, CaseIterable {
    case strip, chevrons, hazard
}

struct TrackSection {
    var deck: DeckPattern
    var wall: WallPattern
    /// Flips the deck texture across the road, so `turn` arrows point left.
    var mirrored = false
}

/// Chooses the texture of every section from the curve: repeating motifs on the
/// fast parts, turn arrows on the approach to a bend, hazard marking inside it.
enum TrackSections {
    static func plan(path: TrackPath) -> [TrackSection] {
        let n = path.sectionCount
        let per = TrackPath.sectionSamples
        let curvature = (0..<n).map { s -> Float in
            (0..<per).reduce(Float(0)) { $0 + path.samples[s * per + $1].curvature } / Float(per)
        }
        var rng = SplitMix64(seed: path.definition.seed &+ 303)
        let accents: [DeckPattern] = [.chevrons, .barcode, .grate, .boost]
        let motifs: [[DeckPattern]] = (0..<3).map { _ in
            [.plain, .chevrons, .plain, accents.randomElement(using: &rng)!,
             .plain, accents.randomElement(using: &rng)!]
        }
        let bend: Float = 0.006, sharp: Float = 0.011

        return (0..<n).map { i in
            let here = curvature[i]
            let ahead = [curvature[(i + 1) % n], curvature[(i + 2) % n]].max { abs($0) < abs($1) }!
            if i == 0 { return TrackSection(deck: .start, wall: .strip) }
            if abs(here) < bend, abs(ahead) >= bend {
                return TrackSection(deck: .turn, wall: .hazard, mirrored: ahead < 0)
            }
            if abs(here) >= sharp { return TrackSection(deck: .hazard, wall: .chevrons) }
            if abs(here) >= bend {
                return TrackSection(deck: i % 2 == 0 ? .turn : .plain, wall: .chevrons, mirrored: here < 0)
            }
            let motif = motifs[(i / 12) % motifs.count]
            return TrackSection(deck: motif[i % motif.count], wall: .strip)
        }
    }
}

/// Sweeps a closed hull cross-section along the path: deck, glowing gutters,
/// slanted barriers and a keeled underside, textured section by section.
enum TrackMeshBuilder {

    /// Profile point: x = halfWidth * `scale` + `offset`, y above the deck.
    private struct Point {
        var scale: Float, offset: Float, y: Float
        func position(_ halfWidth: Float) -> SIMD2<Float> { SIMD2(halfWidth * scale + offset, y) }
    }

    private enum Kind { case deck, gutter, wallRight, wallLeft, hull, belly, barrier }

    /// Counter-clockwise when looking along the track, so every face's outward
    /// normal is on the left of its a→b direction.
    private static let profile: [(a: Point, b: Point, kind: Kind)] = {
        func p(_ scale: Float, _ offset: Float, _ y: Float) -> Point { Point(scale: scale, offset: offset, y: y) }
        let wallHeight: Float = 1.3, keel: Float = -2.6
        return [
            (p(-1, 0, 0), p(1, 0, 0), .deck),
            (p(1, 0, 0), p(1, 0.4, 0), .gutter),
            (p(1, 0.4, 0), p(1, 0.8, wallHeight), .wallRight),
            (p(1, 0.8, wallHeight), p(1, 1.4, wallHeight), .hull),
            (p(1, 1.4, wallHeight), p(1, 1.7, -0.4), .hull),
            (p(1, 1.7, -0.4), p(0.4, 0, keel), .hull),
            (p(0.4, 0, keel), p(-0.4, 0, keel), .belly),
            (p(-0.4, 0, keel), p(-1, -1.7, -0.4), .hull),
            (p(-1, -1.7, -0.4), p(-1, -1.4, wallHeight), .hull),
            (p(-1, -1.4, wallHeight), p(-1, -0.8, wallHeight), .hull),
            (p(-1, -0.8, wallHeight), p(-1, -0.4, 0), .wallLeft),
            (p(-1, -0.4, 0), p(-1, 0, 0), .gutter),
            // Invisible catch fences above the barriers, collision only.
            (p(1, 0.8, wallHeight), p(1, 0.8, 6), .barrier),
            (p(-1, -0.8, 6), p(-1, -0.8, wallHeight), .barrier),
        ]
    }()

    /// Depth of the hull below the deck surface, for anything hung under the track.
    static let keelDepth: Float = 2.6
    /// Distance from the deck edge to the outside of the barrier.
    static let shoulder: Float = 1.7

    private static let gutterSlot = DeckPattern.allCases.count + WallPattern.allCases.count
    private static let hullSlot = gutterSlot + 1
    private static let bellySlot = gutterSlot + 2
    private static let barrierSlot = gutterSlot + 3

    static func buildTrackNode(path: TrackPath) -> SCNNode {
        let theme = path.definition.theme, seed = path.definition.seed
        let sections = TrackSections.plan(path: path)
        let per = TrackPath.sectionSamples
        var mesh = MeshBuilder(materialCount: barrierSlot + 1)

        for (si, section) in sections.enumerated() {
            var previous: [(UInt32, UInt32)] = []
            for row in 0...per {
                let s = path.sample(at: si * per + row)
                let v = Float(row) / Float(per)
                var current: [(UInt32, UInt32)] = []
                for piece in profile {
                    let a = piece.a.position(s.halfWidth), b = piece.b.position(s.halfWidth)
                    let d = b - a
                    let normal = simd_normalize(s.right * -d.y + s.up * d.x)
                    let pa = s.position + s.right * a.x + s.up * a.y
                    let pb = s.position + s.right * b.x + s.up * b.y
                    var ua = SIMD2<Float>(0, v), ub = SIMD2<Float>(1, v)
                    switch piece.kind {
                    case .deck: if section.mirrored { swap(&ua, &ub) }
                    case .wallLeft: swap(&ua, &ub)
                    case .hull:
                        ua = SIMD2(0, v * 2); ub = SIMD2(simd_length(d) / 8, v * 2)
                    case .belly:
                        ua.y = v * 2; ub.y = v * 2
                    case .wallRight, .gutter, .barrier: break
                    }
                    current.append((mesh.vertex(pa, normal, ua), mesh.vertex(pb, normal, ub)))
                }
                if row > 0 {
                    for (pi, piece) in profile.enumerated() {
                        let slot: Int
                        switch piece.kind {
                        case .deck: slot = section.deck.rawValue
                        case .wallRight, .wallLeft: slot = DeckPattern.allCases.count + section.wall.rawValue
                        case .gutter: slot = gutterSlot
                        case .hull: slot = hullSlot
                        case .belly: slot = bellySlot
                        case .barrier: slot = barrierSlot
                        }
                        let (a, b) = previous[pi], (c, d) = current[pi]
                        mesh.quad(slot, a, b, d, c)
                    }
                }
                previous = current
            }
        }

        var materials = DeckPattern.allCases.map {
            ProceduralTextures.deck($0, theme: theme, seed: seed &+ UInt64($0.rawValue))
                .material(name: "deck-\($0)", glow: 2.2)
        }
        materials += WallPattern.allCases.map {
            ProceduralTextures.wall($0, theme: theme, seed: seed &+ 40 &+ UInt64($0.rawValue))
                .material(name: "wall-\($0)", glow: 2.2)
        }
        materials.append(neon(theme.neonA, intensity: 2.5))
        materials.append(hullMaterial(theme: theme, seed: seed))
        materials.append(ProceduralTextures.belly(theme: theme, seed: seed &+ 61).material(name: "belly", glow: 2.5))
        materials.append(SCNMaterial())

        let node = SCNNode(geometry: mesh.geometry(materials: materials, skipping: [barrierSlot]))
        node.name = "trackMesh"
        let body = SCNPhysicsBody(type: .static, shape: SCNPhysicsShape(
            geometry: mesh.collisionGeometry(),
            options: [.type: SCNPhysicsShape.ShapeType.concavePolyhedron]))
        body.categoryBitMask = PhysicsCategory.track
        body.collisionBitMask = PhysicsCategory.car
        node.physicsBody = body

        let root = SCNNode()
        root.name = "trackRoot"
        root.addChildNode(node)
        return root
    }

    /// Structural plating shared by the track hull, pylons and gates (UVs in units of 8 m).
    static func hullMaterial(theme: TrackTheme, seed: UInt64) -> SCNMaterial {
        ProceduralTextures.hull(theme: theme, seed: seed &+ 60).material(name: "hull")
    }

    /// Flat self-lit material for light strips.
    static func neon(_ color: SIMD3<Float>, intensity: CGFloat) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .constant
        let c = UIColor(red: CGFloat(color.x), green: CGFloat(color.y), blue: CGFloat(color.z), alpha: 1)
        m.diffuse.contents = UIColor.black
        m.emission.contents = c
        m.emission.intensity = intensity
        return m
    }
}
