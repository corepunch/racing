import SceneKit
import simd

/// Deck texture of one 16 m section. Each case is a separately generated tile.
enum DeckPattern: Int, CaseIterable {
    case plain, chevrons, bands, hazard, grate, boost, barcode, start
}

enum WallPattern: Int, CaseIterable {
    case strip, blocks, hazard, label
}

struct TrackSection {
    var deck: DeckPattern
    var wall: WallPattern
    var enclosure: Enclosure.Kind? = nil
    /// First and last section of an enclosure get a portal face.
    var portalIn = false
    var portalOut = false
}

/// Chooses the texture of every section from the curve: repeating motifs on the
/// fast parts, colour bands on the approach to a corner, marker blocks through it.
enum TrackSections {
    static func plan(path: TrackPath) -> [TrackSection] {
        let n = path.sectionCount
        let per = TrackPath.sectionSamples
        let curvature = (0..<n).map { s -> Float in
            (0..<per).reduce(Float(0)) { $0 + path.samples[s * per + $1].curvature } / Float(per)
        }
        var rng = SplitMix64(seed: path.definition.seed &+ 303)
        let accents: [DeckPattern] = [.chevrons, .barcode, .grate, .boost, .bands]
        let motifs: [[DeckPattern]] = (0..<3).map { _ in
            [.plain, .chevrons, .plain, accents.randomElement(using: &rng)!,
             .plain, accents.randomElement(using: &rng)!]
        }
        let bend = bendCurvature

        var enclosed = [Enclosure.Kind?](repeating: nil, count: n)
        for e in path.definition.enclosures ?? Enclosure.random(seed: path.definition.seed) {
            let first = max(2, Int((e.start * Float(n)).rounded()))
            let last = min(n - 3, first + max(3, Int((e.length * Float(n)).rounded())))
            guard first <= last else { continue }
            for i in first...last { enclosed[i] = e.kind }
        }

        return (0..<n).map { i -> TrackSection in
            var section = surface(i)
            section.enclosure = enclosed[i]
            section.portalIn = enclosed[i] != nil && enclosed[i - 1] == nil
            section.portalOut = enclosed[i] != nil && enclosed[i + 1] == nil
            return section
        }

        func surface(_ i: Int) -> TrackSection {
            let here = curvature[i]
            let ahead = max(abs(curvature[(i + 1) % n]), abs(curvature[(i + 2) % n]))
            if i == 0 { return TrackSection(deck: .start, wall: .strip) }
            // Colour bands and hazard walls warn of a corner; marker blocks line it.
            if abs(here) < bend, ahead >= bend { return TrackSection(deck: .bands, wall: .hazard) }
            if abs(here) >= bend { return TrackSection(deck: .plain, wall: .blocks) }
            let motif = motifs[(i / 12) % motifs.count]
            return TrackSection(deck: motif[i % motif.count], wall: i % 3 == 1 ? .label : .strip)
        }
    }

    /// Mean curvature (1/m) above which a section counts as part of a corner.
    static let bendCurvature: Float = 0.0035
}

/// Sweeps a closed hull cross-section along the path: deck, glowing gutters,
/// slanted barriers and a keeled underside, textured section by section.
enum TrackMeshBuilder {

    /// Profile point: x = halfWidth * `scale` + `offset`, y above the deck.
    private struct Point {
        var scale: Float, offset: Float, y: Float
        func position(_ halfWidth: Float) -> SIMD2<Float> { SIMD2(halfWidth * scale + offset, y) }
    }

    private enum Kind { case deck, gutter, wallRight, wallLeft, hull, belly, barrier, tunnelWall, tunnelLight }
    private typealias Piece = (a: Point, b: Point, kind: Kind)

    private static let wallHeight: Float = 1.3

    /// Inner and outer rings of an enclosure, right-hand base over the roof to the left-hand base.
    private static func rings(_ kind: Enclosure.Kind) -> (inner: [Point], outer: [Point]) {
        let (margin, height, chamfer) = kind.shape
        let w = 1.4 + margin, thick: Float = 1.6
        let wo = w + thick, ho = height + thick, co = chamfer + 0.7
        func ring(_ base: Float, _ w: Float, _ y: Float, _ h: Float, _ c: Float) -> [Point] {
            [Point(scale: 1, offset: base, y: y), Point(scale: 1, offset: w, y: y),
             Point(scale: 1, offset: w, y: h - c), Point(scale: 1, offset: w - c, y: h),
             Point(scale: -1, offset: -(w - c), y: h), Point(scale: -1, offset: -w, y: h - c),
             Point(scale: -1, offset: -w, y: y), Point(scale: -1, offset: -base, y: y)]
        }
        return (ring(1.4, w, wallHeight, height, chamfer), ring(shoulder, wo, -0.4, ho, co))
    }

    /// Inside faces look inward (walls, light chamfers, ceiling); the shell outside is hull plating.
    private static func enclosureProfile(_ kind: Enclosure.Kind) -> [Piece] {
        let (inner, outer) = rings(kind)
        let kinds: [Kind] = [.hull, .tunnelWall, .tunnelLight, .tunnelWall, .tunnelLight, .tunnelWall, .hull]
        var pieces: [Piece] = (0..<7).map { (inner[$0], inner[$0 + 1], kinds[$0]) }
        pieces += (0..<7).map { (outer[$0 + 1], outer[$0], .hull) }
        return pieces
    }

    /// Counter-clockwise when looking along the track, so every face's outward
    /// normal is on the left of its a→b direction.
    private static let profile: [Piece] = {
        func p(_ scale: Float, _ offset: Float, _ y: Float) -> Point { Point(scale: scale, offset: offset, y: y) }
        let keel: Float = -2.6
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
    private static let tunnelWallSlot = gutterSlot + 4
    private static let tunnelLightSlot = gutterSlot + 5

    static func buildTrackNode(path: TrackPath) -> SCNNode {
        let theme = path.definition.theme, seed = path.definition.seed
        let sections = TrackSections.plan(path: path)
        let per = TrackPath.sectionSamples
        var mesh = MeshBuilder(materialCount: tunnelLightSlot + 1)
        let enclosures: [Enclosure.Kind: [Piece]] = [.tunnel: enclosureProfile(.tunnel), .hall: enclosureProfile(.hall)]

        for (si, section) in sections.enumerated() {
            let pieces = profile + (section.enclosure.flatMap { enclosures[$0] } ?? [])
            var previous: [(UInt32, UInt32)] = []
            for row in 0...per {
                let s = path.sample(at: si * per + row)
                let v = Float(row) / Float(per)
                var current: [(UInt32, UInt32)] = []
                for piece in pieces {
                    let a = piece.a.position(s.halfWidth), b = piece.b.position(s.halfWidth)
                    let d = b - a
                    let normal = simd_normalize(s.right * -d.y + s.up * d.x)
                    let pa = s.position + s.right * a.x + s.up * a.y
                    let pb = s.position + s.right * b.x + s.up * b.y
                    var ua = SIMD2<Float>(0, v), ub = SIMD2<Float>(1, v)
                    switch piece.kind {
                    case .deck: break
                    case .wallLeft:
                        swap(&ua, &ub)
                        // Lettering must not come out mirrored on the opposite wall.
                        if section.wall == .label { ua.y = 1 - v; ub.y = 1 - v }
                    case .hull:
                        ua = SIMD2(0, v * 2); ub = SIMD2(simd_length(d) / 8, v * 2)
                    case .belly:
                        ua.y = v * 2; ub.y = v * 2
                    case .tunnelWall:
                        // Ceiling is centred on the road; walls start at the walkway.
                        if abs(d.x) > abs(d.y) {
                            ua.x = a.x / 8 + 0.5; ub.x = b.x / 8 + 0.5
                        } else {
                            ua.x = (a.y - wallHeight) / 8; ub.x = (b.y - wallHeight) / 8
                        }
                    case .wallRight, .gutter, .barrier, .tunnelLight: break
                    }
                    current.append((mesh.vertex(pa, normal, ua), mesh.vertex(pb, normal, ub)))
                }
                if row > 0 {
                    for (pi, piece) in pieces.enumerated() {
                        let slot: Int
                        switch piece.kind {
                        case .deck: slot = section.deck.rawValue
                        case .wallRight, .wallLeft: slot = DeckPattern.allCases.count + section.wall.rawValue
                        case .gutter: slot = gutterSlot
                        case .hull: slot = hullSlot
                        case .belly: slot = bellySlot
                        case .barrier: slot = barrierSlot
                        case .tunnelWall: slot = tunnelWallSlot
                        case .tunnelLight: slot = tunnelLightSlot
                        }
                        let (a, b) = previous[pi], (c, d) = current[pi]
                        mesh.quad(slot, a, b, d, c)
                    }
                }
                previous = current
            }
            // Portal faces close the gap between the inner and outer rings.
            if let kind = section.enclosure {
                for (exit, row) in [(false, 0), (true, per)] where exit ? section.portalOut : section.portalIn {
                    let s = path.sample(at: si * per + row)
                    let normal = simd_cross(s.up, s.right) * (exit ? 1 : -1)
                    let (inner, outer) = rings(kind)
                    func vertex(_ p: Point) -> UInt32 {
                        let q = p.position(s.halfWidth)
                        return mesh.vertex(s.position + s.right * q.x + s.up * q.y, normal, q / 8)
                    }
                    for k in 0..<7 {
                        let i0 = vertex(inner[k]), i1 = vertex(inner[k + 1])
                        let o0 = vertex(outer[k]), o1 = vertex(outer[k + 1])
                        if exit { mesh.quad(hullSlot, i0, i1, o1, o0) } else { mesh.quad(hullSlot, i0, o0, o1, i1) }
                    }
                }
            }
        }

        var materials = DeckPattern.allCases.map {
            ProceduralTextures.deck($0, theme: theme, seed: seed &+ UInt64($0.rawValue))
                .material(name: "deck-\($0)", glow: 1.8)
        }
        materials += WallPattern.allCases.map {
            ProceduralTextures.wall($0, theme: theme, seed: seed &+ 40 &+ UInt64($0.rawValue),
                                    label: "\(path.definition.name.uppercased())  //  MAGLOCK ZONE")
                .material(name: "wall-\($0)", glow: 1)
        }
        // Gutter: a plain painted channel.
        let gutter = SCNMaterial()
        gutter.lightingModel = .physicallyBased
        gutter.diffuse.contents = UIColor(white: 0.62, alpha: 1)
        gutter.roughness.contents = 0.6
        gutter.metalness.contents = 0
        materials.append(gutter)
        materials.append(hullMaterial(theme: theme, seed: seed))
        materials.append(ProceduralTextures.belly(theme: theme, seed: seed &+ 61).material(name: "belly", glow: 1.6))
        materials.append(SCNMaterial())
        materials.append(ProceduralTextures.tunnelWall(theme: theme, seed: seed &+ 62)
            .material(name: "tunnel-wall", glow: 2.2))
        materials.append(ProceduralTextures.tunnelLight(theme: theme, seed: seed &+ 63)
            .material(name: "tunnel-light", glow: 2.6))

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
