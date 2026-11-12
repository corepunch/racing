import SceneKit
import simd

/// Procedural start/finish structures: gantry, chequered line, flags and grandstands.
enum RaceProps {

    // MARK: - Frames and materials

    /// Horizontal frame at a sample: x = right, y = world up, z = backwards (toward approaching cars).
    private static func frame(_ s: PathSample) -> simd_float3x3 {
        let fwd = simd_normalize(SIMD3(s.forward.x, 0, s.forward.z))
        let up = SIMD3<Float>(0, 1, 0)
        return simd_float3x3(columns: (simd_cross(fwd, up), up, -fwd))
    }

    private static func pbr(_ contents: Any, metal: CGFloat = 0, roughness: CGFloat = 0.8,
                            scale: SIMD2<Float>? = nil, emission: UIColor? = nil,
                            doubleSided: Bool = false) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = contents
        m.metalness.contents = metal
        m.roughness.contents = roughness
        m.isDoubleSided = doubleSided
        if let scale {
            m.diffuse.wrapS = .repeat
            m.diffuse.wrapT = .repeat
            m.diffuse.mipFilter = .linear
            m.diffuse.maxAnisotropy = 8
            m.diffuse.contentsTransform = SCNMatrix4MakeScale(scale.x, scale.y, 1)
        }
        if let emission { m.emission.contents = emission }
        return m
    }

    private static let steel = pbr(UIColor(white: 0.62, alpha: 1), metal: 0.8, roughness: 0.4)
    private static let darkSteel = pbr(UIColor(white: 0.16, alpha: 1), metal: 0.6, roughness: 0.5)

    /// 2 × 2 chequer cells per texture tile.
    private static let chequer: UIImage = ProceduralTextures.image(width: 64, height: 64) { u, v in
        ((u < 0.5) != (v < 0.5)) ? SIMD3(repeating: 0.06) : SIMD3(repeating: 0.94)
    }

    /// Chequer border with text; drawn with UIKit so the lettering is crisp.
    private static func banner(_ text: String, width: Int = 1024, height: Int = 128,
                               fill: UIColor, textColor: UIColor = .white) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { ctx in
            let g = ctx.cgContext
            fill.setFill()
            g.fill(CGRect(x: 0, y: 0, width: width, height: height))
            let cell = CGFloat(height) / 8
            for row in 0..<2 {
                let y = row == 0 ? 0 : CGFloat(height) - cell
                for col in 0..<Int(CGFloat(width) / cell) where (col + row) % 2 == 0 {
                    UIColor.black.setFill()
                    g.fill(CGRect(x: CGFloat(col) * cell, y: y, width: cell, height: cell))
                }
                UIColor.white.setFill()
                for col in 0..<Int(CGFloat(width) / cell) where (col + row) % 2 == 1 {
                    g.fill(CGRect(x: CGFloat(col) * cell, y: y, width: cell, height: cell))
                }
            }
            let font = UIFont.systemFont(ofSize: CGFloat(height) * 0.5, weight: .black)
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor, .kern: 6]
            let size = (text as NSString).size(withAttributes: attrs)
            (text as NSString).draw(at: CGPoint(x: (CGFloat(width) - size.width) / 2,
                                                y: (CGFloat(height) - size.height) / 2), withAttributes: attrs)
        }
    }

    /// Row of sponsor boards for grandstand fronts; one tile = 3 boards.
    private static let adverts: UIImage = {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let boards: [(String, UIColor, UIColor)] = [
            ("TURBO", UIColor(red: 0.85, green: 0.1, blue: 0.08, alpha: 1), .white),
            ("NITRO OIL", UIColor(red: 0.98, green: 0.8, blue: 0.1, alpha: 1), .black),
            ("APEX", UIColor(red: 0.05, green: 0.25, blue: 0.7, alpha: 1), .white),
        ]
        return UIGraphicsImageRenderer(size: CGSize(width: 1536, height: 128), format: format).image { ctx in
            for (k, board) in boards.enumerated() {
                let rect = CGRect(x: k * 512, y: 0, width: 512, height: 128)
                board.1.setFill()
                ctx.cgContext.fill(rect)
                UIColor(white: 0.1, alpha: 1).setFill()
                ctx.cgContext.fill(CGRect(x: rect.maxX - 6, y: 0, width: 6, height: 128))
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 76, weight: .heavy), .foregroundColor: board.2]
                let size = (board.0 as NSString).size(withAttributes: attrs)
                (board.0 as NSString).draw(at: CGPoint(x: rect.midX - size.width / 2, y: 64 - size.height / 2),
                                           withAttributes: attrs)
            }
        }
    }()

    // MARK: - Start gantry and line

    static func startGantry(sample s: PathSample) -> SCNNode {
        let basis = frame(s)
        let x = basis.columns.0, up = basis.columns.1, back = basis.columns.2
        let base = s.position
        let span: Float = 9.2
        let half = span - 0.5
        let bannerMat = pbr(banner("START  ·  FINISH", fill: UIColor(red: 0.75, green: 0.06, blue: 0.06, alpha: 1)),
                            roughness: 0.7, scale: SIMD2(1 / (2 * half), -1 / 1.4))
        let lamp = pbr(UIColor(red: 0.3, green: 0, blue: 0, alpha: 1),
                       emission: UIColor(red: 1, green: 0.08, blue: 0.05, alpha: 1))
        let line = pbr(chequer, roughness: 0.75, scale: SIMD2(1, 1))
        enum Slot: Int { case steel, dark, banner, lamp, line }
        var mb = MeshBuilder(materialCount: 5)

        for side: Float in [-1, 1] {
            mb.box(Slot.steel.rawValue, origin: base + x * (span * side) - up * 0.6, basis: basis,
                   size: SIMD3(0.8, 9.4, 0.8))
            mb.box(Slot.dark.rawValue, origin: base + x * (span * side) - up * 0.2, basis: basis,
                   size: SIMD3(1.3, 0.5, 1.3))
        }
        // Twin truss chords with a deep banner box between them.
        for y: Float in [6.9, 8.6] {
            mb.box(Slot.steel.rawValue, origin: base + up * y, basis: basis, size: SIMD3(span * 2 + 0.8, 0.3, 0.9))
        }
        mb.box(Slot.dark.rawValue, origin: base + up * 7.2, basis: basis, size: SIMD3(span * 2 - 0.8, 1.4, 0.5))
        for face: Float in [1, -1] {
            let o = base + up * 7.2 + back * (0.26 * face)
            let l = x * (-half * face), r = x * (half * face)
            mb.flatQuad(Slot.banner.rawValue, o + l, o + r, o + r + up * 1.4, o + l + up * 1.4)
        }
        // Start lights hanging under the gantry, facing the grid.
        mb.box(Slot.dark.rawValue, origin: base + up * 5.9, basis: basis, size: SIMD3(5.6, 0.9, 0.45))
        for k in 0..<5 {
            let lx = (Float(k) - 2) * 1.05
            mb.box(Slot.lamp.rawValue, origin: base + x * lx + up * 6.08 + back * 0.25, basis: basis,
                   size: SIMD3(0.5, 0.5, 0.1))
        }
        for k in 0..<2 {
            mb.box(Slot.steel.rawValue, origin: base + x * (Float(k) * 4 - 2) + up * 6.8, basis: basis,
                   size: SIMD3(0.1, 0.4, 0.1))
        }

        // Chequered line painted across the (possibly banked) road: 2 rows of 0.5 m squares.
        let lift = s.up * 0.015
        let a = s.position + s.right * -s.halfWidth - s.forward * 0.5 + lift
        let b = s.position + s.right * s.halfWidth - s.forward * 0.5 + lift
        let c = s.position + s.right * s.halfWidth + s.forward * 0.5 + lift
        let d = s.position + s.right * -s.halfWidth + s.forward * 0.5 + lift
        mb.flatQuad(Slot.line.rawValue, a, b, c, d)

        let node = SCNNode(geometry: mb.geometry(materials: [steel, darkSteel, bannerMat, lamp, line]))
        node.name = "startGantry"
        PhysicsCategory.addStaticMesh(to: node, category: PhysicsCategory.obstacle)
        return node
    }

    // MARK: - Flags

    static func flag(sample s: PathSample, side: Float) -> SCNNode {
        let basis = frame(s)
        let x = basis.columns.0, up = basis.columns.1, back = basis.columns.2
        let cloth = pbr(chequer, roughness: 0.9, scale: SIMD2(1, 1), doubleSided: true)
        var mb = MeshBuilder(materialCount: 2)
        let foot = s.position + x * (side * 11.2) - up * 0.4
        let height: Float = 6.5
        mb.box(0, origin: foot, basis: basis, size: SIMD3(0.12, height + 0.4, 0.12))

        // Cloth flies backwards from the pole top with a travelling ripple.
        let cols = 8, rows = 4
        let length: Float = 2.4, drop: Float = 1.5
        let top = foot + up * (height + 0.35)
        var grid = [[UInt32]]()
        for j in 0...rows {
            var row = [UInt32]()
            for i in 0...cols {
                let u = Float(i) / Float(cols), v = Float(j) / Float(rows)
                let ripple = sin(u * 7 - v * 0.8) * 0.18 * u
                let p = top + back * (u * length) - up * (v * drop + u * u * 0.25) + x * ripple
                row.append(mb.vertex(p, x, SIMD2(u * 4, v * 2.5)))
            }
            grid.append(row)
        }
        for j in 0..<rows {
            for i in 0..<cols {
                mb.quad(1, grid[j][i], grid[j + 1][i], grid[j + 1][i + 1], grid[j][i + 1])
            }
        }
        let node = SCNNode(geometry: mb.geometry(materials: [steel, cloth]))
        node.name = "startFlag"
        PhysicsCategory.addStaticMesh(to: node, category: PhysicsCategory.obstacle)
        return node
    }

    // MARK: - Grandstand

    /// Covered stand facing the road, `length` metres along the track, front edge `front` m from the centreline.
    /// Returns nil when the footprint would touch any road.
    static func grandstand(sample s: PathSample, side: Float, field: TerrainField,
                           length: Float = 36, front: Float = 15, seed: UInt64 = 1) -> SCNNode? {
        let fwd = simd_normalize(SIMD3(s.forward.x, 0, s.forward.z))
        let rightH = simd_normalize(SIMD3(s.right.x, 0, s.right.z))
        let toRoad = -rightH * side
        let up = SIMD3<Float>(0, 1, 0)
        let basis = simd_float3x3(columns: (simd_cross(up, toRoad), up, toRoad))
        let ax = basis.columns.0

        let tiers = 10
        let tread: Float = 0.85, rise: Float = 0.45
        let depth = Float(tiers) * tread + 0.6
        let frontPoint = s.position + rightH * side * front

        var ground = Float.greatestFiniteMagnitude
        for cx: Float in [-0.5, 0, 0.5] {
            for cz: Float in [0, 1] {
                let p = frontPoint + ax * (cx * length) - toRoad * (cz * depth)
                let info = field.info(p.x, p.z)
                if info.hit.distance < front - 2.5 { return nil }
                ground = min(ground, info.height)
            }
        }
        let origin = SIMD3(frontPoint.x, ground, frontPoint.z)
        func at(_ lx: Float, _ ly: Float, _ lz: Float) -> SIMD3<Float> { origin + basis * SIMD3(lx, ly, lz) }

        enum Slot: Int { case concrete, seat, steel, roof, ads }
        let concrete = pbr(ProceduralTextures.concrete(seed: 35), roughness: 0.9, scale: SIMD2(0.25, 0.25))
        let seat = pbr(UIColor.white, roughness: 0.6)
        let roof = pbr(UIColor(white: 0.85, alpha: 1), metal: 0.3, roughness: 0.5, doubleSided: true)
        let ads = pbr(adverts, roughness: 0.6, scale: SIMD2(1.0 / 12.0, -1.0 / 1.2))
        var mb = MeshBuilder(materialCount: 5, colors: true)
        var rng = SplitMix64(seed: seed)
        let team: [SIMD3<Float>] = [SIMD3(0.8, 0.08, 0.06), SIMD3(0.06, 0.25, 0.75), SIMD3(0.95, 0.75, 0.08),
                                    SIMD3(0.1, 0.55, 0.2), SIMD3(0.92, 0.92, 0.9)]
        let colorA = team[Int(rng.next() % 5)]
        var colorB = team[Int(rng.next() % 5)]
        if colorB == colorA { colorB = team[(team.firstIndex(of: colorA)! + 1) % 5] }

        let sink: Float = 2
        let podium: Float = 1.6
        // Front wall carrying the advert boards.
        mb.box(Slot.concrete.rawValue, origin: at(0, -sink, -0.15), basis: basis,
               size: SIMD3(length, sink + podium, 0.3))
        mb.flatQuad(Slot.ads.rawValue, at(-length / 2, 0.3, 0.01), at(length / 2, 0.3, 0.01),
                    at(length / 2, 1.5, 0.01), at(-length / 2, 1.5, 0.01))

        // Solid stepped terraces with a row of seats on each step.
        for t in 0..<tiers {
            let top = podium + Float(t) * rise
            let zc = -0.3 - (Float(t) + 0.5) * tread
            mb.box(Slot.concrete.rawValue, origin: at(0, -sink, zc), basis: basis,
                   size: SIMD3(length, top + sink, tread))
            let seats = Int((length - 1.2) / 0.55)
            for k in 0..<seats {
                let lx = -length / 2 + 0.6 + (Float(k) + 0.5) * 0.55
                let block = Int((lx + length / 2) / 6)
                let c = (block + t / 3) % 2 == 0 ? colorA : colorB
                mb.box(Slot.seat.rawValue, origin: at(lx, top, zc + 0.1), basis: basis,
                       size: SIMD3(0.44, 0.38, 0.38), color: c)
                mb.box(Slot.seat.rawValue, origin: at(lx, top + 0.38, zc - 0.12), basis: basis,
                       size: SIMD3(0.44, 0.4, 0.08), color: c * 0.85)
            }
        }

        // Back and side walls, rear columns and a cantilevered roof.
        let topStep = podium + Float(tiers) * rise
        let backZ = -depth
        let roofBack = topStep + 4.2, roofFront = topStep + 4.9
        mb.box(Slot.concrete.rawValue, origin: at(0, -sink, backZ - 0.15), basis: basis,
               size: SIMD3(length, roofBack + sink, 0.3))
        for sx: Float in [-1, 1] {
            mb.box(Slot.concrete.rawValue, origin: at(sx * (length / 2 + 0.15), -sink, backZ / 2), basis: basis,
                   size: SIMD3(0.3, topStep + 1.2 + sink, -backZ))
        }
        var cx = -length / 2
        while cx <= length / 2 + 0.01 {
            mb.box(Slot.steel.rawValue, origin: at(cx, topStep, backZ + 0.4), basis: basis,
                   size: SIMD3(0.35, roofBack - topStep, 0.35))
            mb.box(Slot.steel.rawValue, origin: at(cx, roofBack - 0.35, backZ / 2 + 0.6), basis: basis,
                   size: SIMD3(0.25, 0.3, -backZ + 1.6))
            cx += 6
        }
        let r0 = at(-length / 2 - 0.5, roofBack, backZ - 0.4), r1 = at(length / 2 + 0.5, roofBack, backZ - 0.4)
        let r2 = at(length / 2 + 0.5, roofFront, 1.2), r3 = at(-length / 2 - 0.5, roofFront, 1.2)
        mb.flatQuad(Slot.roof.rawValue, r0, r3, r2, r1)

        let node = SCNNode(geometry: mb.geometry(materials: [concrete, seat, steel, roof, ads]))
        node.name = "grandstand"
        PhysicsCategory.addStaticMesh(to: node, category: PhysicsCategory.obstacle)
        return node
    }
}
