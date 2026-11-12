import SceneKit
import simd

/// Procedural scenery generated from a track definition: tunnels, guardrails, towns and forests.
enum TrackScenery {

    static func build(field: TerrainField, terrainMaterial: SCNMaterial) -> SCNNode {
        let root = SCNNode()
        root.name = "scenery"
        let path = field.path
        for range in zoneRanges(path, kind: .tunnel) {
            root.addChildNode(tunnel(path: path, range: range, coverMaterial: terrainMaterial))
        }
        root.addChildNode(guardrails(path: path))
        for range in zoneRanges(path, kind: .town) {
            root.addChildNode(town(field: field, range: range))
        }
        root.addChildNode(ForestBuilder.build(field: field))
        return root
    }

    /// Contiguous sample index ranges for a zone kind (end exclusive; may exceed count to wrap).
    static func zoneRanges(_ path: TrackPath, kind: TrackDefinition.Zone.Kind) -> [Range<Int>] {
        let n = path.stepCount
        var ranges = [Range<Int>]()
        var i = 0
        while i < n {
            if path.samples[i].zone == kind {
                let start = i
                while i < n && path.samples[i].zone == kind { i += 1 }
                ranges.append(start..<i)
            } else {
                i += 1
            }
        }
        return ranges
    }

    // MARK: - Materials

    private static func textured(_ image: UIImage, scale: SIMD2<Float>, roughness: CGFloat = 0.9,
                                 doubleSided: Bool = false) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = image
        m.diffuse.wrapS = .repeat
        m.diffuse.wrapT = .repeat
        m.diffuse.mipFilter = .linear
        m.diffuse.maxAnisotropy = 8
        m.diffuse.contentsTransform = SCNMatrix4MakeScale(scale.x, scale.y, 1)
        m.roughness.contents = roughness
        m.metalness.contents = 0
        m.isDoubleSided = doubleSided
        return m
    }

    private static func color(_ c: SIMD3<Float>, metal: CGFloat = 0, roughness: CGFloat = 0.8,
                              emission: SIMD3<Float>? = nil) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = UIColor(red: CGFloat(c.x), green: CGFloat(c.y), blue: CGFloat(c.z), alpha: 1)
        m.metalness.contents = metal
        m.roughness.contents = roughness
        if let e = emission {
            m.emission.contents = UIColor(red: CGFloat(e.x), green: CGFloat(e.y), blue: CGFloat(e.z), alpha: 1)
        }
        return m
    }

    private static let concrete = ProceduralTextures.concrete(seed: 77)

    // MARK: - Tunnels

    /// Inner tube profile (lateral, height) from right floor, over the arch, to left floor.
    private static let tubeProfile: [SIMD2<Float>] = {
        var p: [SIMD2<Float>] = [SIMD2(8.6, -0.6), SIMD2(8.6, 4.2)]
        let steps = 20
        for k in 1..<steps {
            let a = Float(k) / Float(steps) * .pi
            p.append(SIMD2(8.6 * cos(a), 4.2 + 4.0 * sin(a)))
        }
        p += [SIMD2(-8.6, 4.2), SIMD2(-8.6, -0.6)]
        return p
    }()

    private static func tunnel(path: TrackPath, range: Range<Int>, coverMaterial: SCNMaterial) -> SCNNode {
        let wall = textured(concrete, scale: SIMD2(0.25, 0.25), doubleSided: true)
        let lamp = color(SIMD3(1, 0.9, 0.7), emission: SIMD3(1.0, 0.86, 0.6))
        let portal = textured(concrete, scale: SIMD2(0.25, -0.25), doubleSided: true)
        let stripe = color(SIMD3(0.9, 0.75, 0.1), roughness: 0.6)
        var mb = MeshBuilder(materialCount: 4)
        let first = range.lowerBound - 1, last = range.upperBound
        let indices = Array(first...last)
        let prof = tubeProfile

        // Profile arc length for u.
        var profU = [Float](repeating: 0, count: prof.count)
        for k in 1..<prof.count { profU[k] = profU[k - 1] + simd_length(prof[k] - prof[k - 1]) }

        // Tube walls with inward normals.
        var prevRow: [UInt32] = []
        for idx in indices {
            let s = path.sample(at: idx)
            var row: [UInt32] = []
            for (k, p) in prof.enumerated() {
                let pos = s.position + s.right * p.x + s.up * p.y
                var n2: SIMD2<Float>
                if p.y <= 4.2 + 1e-3 { n2 = SIMD2(-sgn(p.x), 0) } else {
                    n2 = -simd_normalize(SIMD2(p.x / (8.6 * 8.6), (p.y - 4.2) / 16))
                }
                let n = s.right * n2.x + s.up * n2.y
                row.append(mb.vertex(pos, n, SIMD2(profU[k], Float(idx - first) * 2)))
            }
            if !prevRow.isEmpty {
                for k in 0..<(prof.count - 1) {
                    mb.quad(0, prevRow[k], prevRow[k + 1], row[k + 1], row[k])
                }
            }
            prevRow = row
        }

        // Ceiling lights: 3 m lamps every 8 m along both sides of the crown.
        for idx in stride(from: range.lowerBound, to: range.upperBound - 1, by: 4) {
            let a = path.sample(at: idx), b = path.sample(at: idx + 1)
            for side: Float in [-1.6, 1.6] {
                let y: Float = 8.05
                let w: Float = 0.35
                let p0 = a.position + a.right * (side - w) + a.up * y
                let p1 = a.position + a.right * (side + w) + a.up * y
                let p2 = b.position + b.right * (side + w) + b.up * y
                let p3 = b.position + b.right * (side - w) + b.up * y
                mb.flatQuad(1, p0, p3, p2, p1)
            }
        }
        // Yellow hazard band along the lower walls.
        for idx in first..<last {
            let a = path.sample(at: idx), b = path.sample(at: idx + 1)
            for side: Float in [-1, 1] {
                let x: Float = 8.58 * side
                let p0 = a.position + a.right * x + a.up * 0.4, p1 = b.position + b.right * x + b.up * 0.4
                let p2 = b.position + b.right * x + b.up * 1.0, p3 = a.position + a.right * x + a.up * 1.0
                if side > 0 { mb.flatQuad(3, p1, p0, p3, p2) } else { mb.flatQuad(3, p0, p1, p2, p3) }
            }
        }

        // Portals: concrete headwall with an arched opening.
        for (idx, outward) in [(first + 1, Float(-1)), (last - 1, Float(1))] {
            let s = path.sample(at: idx)
            let fwd = s.forward * outward
            let base = s.position + fwd * 0.2
            let outer: (x: Float, top: Float, bottom: Float) = (21, 13, -1.2)
            let center = SIMD2<Float>(0, 3.5)
            func toWorld(_ p: SIMD2<Float>) -> SIMD3<Float> { base + s.right * p.x + s.up * p.y }
            func boundary(_ p: SIMD2<Float>) -> SIMD2<Float> {
                if p.y <= -0.59 { return SIMD2(sgn(p.x) * outer.x, outer.bottom) }
                let d = simd_normalize(p - center)
                let tx = d.x != 0 ? outer.x / abs(d.x) : .infinity
                let ty = d.y > 0 ? (outer.top - center.y) / d.y : .infinity
                return center + d * min(tx, ty)
            }
            for k in 0..<(prof.count - 1) {
                let a = prof[k], b = prof[k + 1]
                let oa = boundary(a), ob = boundary(b)
                let n = fwd
                let ia = mb.vertex(toWorld(a), n, a), ib = mb.vertex(toWorld(b), n, b)
                let ioa = mb.vertex(toWorld(oa), n, oa), iob = mb.vertex(toWorld(ob), n, ob)
                let aOnSide = abs(abs(oa.x) - outer.x) < 1e-3, bOnSide = abs(abs(ob.x) - outer.x) < 1e-3
                if aOnSide != bOnSide {
                    let corner = SIMD2(sgn(oa.x) * outer.x, outer.top)
                    let cornerPt = aOnSide ? corner : SIMD2(sgn(ob.x) * outer.x, outer.top)
                    let ic = mb.vertex(toWorld(cornerPt), n, cornerPt)
                    mb.triangle(2, ia, ioa, ic)
                    mb.triangle(2, ia, ic, iob)
                    mb.triangle(2, ia, iob, ib)
                } else {
                    mb.quad(2, ia, ioa, iob, ib)
                }
            }
            // Cornice along the top of the headwall.
            mb.box(2, origin: toWorld(SIMD2(0, outer.top)) - fwd * 0.6,
                   basis: simd_float3x3(columns: (s.right, s.up, fwd)),
                   size: SIMD3(outer.x * 2 + 1, 0.8, 1.6))
        }

        let node = SCNNode(geometry: mb.geometry(materials: [wall, lamp, portal, stripe]))
        node.name = "tunnel"

        // Earth cover over the tube so the mountain reads as continuous from outside.
        var cover = MeshBuilder(materialCount: 1)
        let xs: [Float] = stride(from: -17, through: 17, by: 1.7).map { $0 }
        var prev: [UInt32] = []
        for idx in indices {
            let s = path.sample(at: idx)
            var row: [UInt32] = []
            for x in xs {
                let h = 10 + s.tunnelHill * s.tunnelDepth * exp(-pow(max(abs(x) - 15, 0) / 90, 2))
                let p = s.position + s.right * x + SIMD3(0, h, 0)
                row.append(cover.vertex(p, SIMD3(0, 1, 0), SIMD2(p.x, p.z)))
            }
            if !prev.isEmpty {
                for k in 0..<(xs.count - 1) { cover.quad(0, prev[k], prev[k + 1], row[k + 1], row[k]) }
            }
            prev = row
        }
        let coverNode = SCNNode(geometry: cover.geometry(materials: [coverMaterial]))
        node.addChildNode(coverNode)
        return node
    }

    // MARK: - Guardrails

    private static func guardrails(path: TrackPath) -> SCNNode {
        let metal = color(SIMD3(0.72, 0.74, 0.76), metal: 0.7, roughness: 0.35)
        metal.isDoubleSided = true
        let postMat = color(SIMD3(0.45, 0.46, 0.48), metal: 0.5, roughness: 0.5)
        var mb = MeshBuilder(materialCount: 2)
        let n = path.stepCount
        for side: Float in [-1, 1] {
            var prev: (UInt32, UInt32)?
            for i in 0...n {
                let s = path.sample(at: i)
                let open = s.zone == nil && s.townInfluence < 0.3 && s.tunnelInfluence < 0.85
                    && !(s.arcLength < 70 || s.arcLength > path.totalLength - 50)
                guard open else { prev = nil; continue }
                let lateral = side * (s.halfWidth + 3.6)
                let base = s.position + s.right * lateral
                let nrm = -s.right * side
                let lo = mb.vertex(base + s.up * 0.5, nrm, SIMD2(s.arcLength, 0))
                let hi = mb.vertex(base + s.up * 0.85, nrm, SIMD2(s.arcLength, 0.35))
                if let (plo, phi) = prev {
                    if side > 0 { mb.quad(0, plo, lo, hi, phi) } else { mb.quad(0, lo, plo, phi, hi) }
                }
                prev = (lo, hi)
                if i % 2 == 0 {
                    let back = s.right * side * 0.12
                    mb.box(1, origin: base + back - SIMD3(0, 0.4, 0),
                           basis: simd_float3x3(columns: (s.right, SIMD3(0, 1, 0), -s.forward)),
                           size: SIMD3(0.14, 1.2, 0.14), top: true)
                }
            }
        }
        let node = SCNNode(geometry: mb.geometry(materials: [metal, postMat]))
        node.name = "guardrails"
        return node
    }

    // MARK: - Towns

    private static func town(field: TerrainField, range: Range<Int>) -> SCNNode {
        let path = field.path
        let env = field.env
        let palette = env.palette
        var rng = SplitMix64(seed: env.seed &+ UInt64(range.lowerBound))

        // Slots: upper facades [0, nf), matching ground floors [nf, 2nf), then shared extras.
        let nf = palette.facades.count
        var materials = palette.facades.enumerated().map { k, c in
            textured(ProceduralTextures.facade(wall: c, seed: env.seed &+ UInt64(k * 13 + 1)),
                     scale: SIMD2(1.0 / 6.0, -1.0 / 3.0), roughness: 0.85)
        }
        materials += palette.facades.enumerated().map { k, c in
            textured(ProceduralTextures.groundFloor(wall: c, shop: k % 2 == 0, seed: env.seed &+ UInt64(k * 7 + 3)),
                     scale: SIMD2(1.0 / 6.0, -1.0 / 3.6), roughness: 0.8)
        }
        let sRoof = 2 * nf, sSlate = sRoof + 1, sFlat = sRoof + 2, sTrim = sRoof + 3
        let sMetal = sRoof + 4, sGlass = sRoof + 5, sAwning = sRoof + 6
        materials += [
            textured(ProceduralTextures.roof(color: palette.roof, seed: env.seed &+ 5),
                     scale: SIMD2(0.25, 0.25), roughness: 0.8, doubleSided: true),
            textured(ProceduralTextures.slateRoof(seed: env.seed &+ 8), scale: SIMD2(0.25, 0.25),
                     roughness: 0.6, doubleSided: true),
            textured(ProceduralTextures.flatRoof(seed: env.seed &+ 6), scale: SIMD2(0.2, 0.2)),
            textured(ProceduralTextures.stoneTrim(seed: env.seed &+ 9), scale: SIMD2(0.5, 0.5)),
            color(SIMD3(0.16, 0.17, 0.18), metal: 0.6, roughness: 0.45),
            color(SIMD3(1, 0.95, 0.8), emission: SIMD3(1, 0.9, 0.7)),
            textured(ProceduralTextures.awning(seed: env.seed &+ 10), scale: SIMD2(0.5, 1), roughness: 0.9,
                     doubleSided: true),
        ]
        var mb = MeshBuilder(materialCount: materials.count)

        struct Placed { var corners: [SIMD2<Float>] }
        var placed = [Placed]()
        let up = SIMD3<Float>(0, 1, 0)
        let groundH: Float = 3.6

        for side: Float in [-1, 1] {
            var arc = path.sample(at: range.lowerBound).arcLength + rng.float(0...6)
            let endArc = path.sample(at: range.upperBound - 1).arcLength
            while arc < endArc - 6 {
                let width = rng.float(8...15)
                let depth = rng.float(8...13)
                let gap = rng.float(0.5...3.5)
                let mid = path.sample(at: Int((arc + width / 2) / path.totalLength * Float(path.stepCount)))
                arc += width + gap
                if rng.float() < 0.08 { continue }

                let rightH = simd_normalize(SIMD3(mid.right.x, 0, mid.right.z))
                let towardRoad = -rightH * side
                let xAxis = simd_cross(up, towardRoad)
                let basis = simd_float3x3(columns: (xAxis, up, towardRoad))
                let front = rng.float(13.4...15)
                let centerXZ = mid.position + rightH * side * (front + depth / 2)

                // Footprint must stay clear of every stretch of road and of other buildings.
                var clear = true
                var minGround = Float.greatestFiniteMagnitude, maxGround = -Float.greatestFiniteMagnitude
                for cx: Float in [-0.5, 0.5] {
                    for cz: Float in [-0.5, 0.5] {
                        let p = centerXZ + xAxis * (cx * width) + towardRoad * (cz * depth)
                        let info = field.info(p.x, p.z)
                        if info.hit.distance < 12.8 { clear = false }
                        minGround = min(minGround, info.height)
                        maxGround = max(maxGround, info.height)
                    }
                }
                let c2 = SIMD2(centerXZ.x, centerXZ.z)
                let ax = SIMD2(xAxis.x, xAxis.z), az = SIMD2(towardRoad.x, towardRoad.z)
                let rect = [c2 - ax * width / 2 - az * depth / 2, c2 + ax * width / 2 - az * depth / 2,
                            c2 + ax * width / 2 + az * depth / 2, c2 - ax * width / 2 + az * depth / 2]
                if placed.contains(where: { rectsOverlap($0.corners, rect) }) { clear = false }
                guard clear else { continue }
                placed.append(Placed(corners: rect))

                let gabled: Bool
                switch env.roofStyle {
                case .gabled: gabled = true
                case .flat: gabled = false
                case .mixed: gabled = rng.float() < 0.5
                }
                let floors = Int(rng.float(2...(gabled ? 4.6 : 6.6)))
                let height = groundH + Float(floors - 1) * 3 + 0.3
                let floorY = maxGround + 0.3
                let baseY = minGround - 2
                let hx = width / 2, hz = depth / 2
                // Local coordinates: y relative to the ground-floor level, +z out of the street facade.
                func p(_ x: Float, _ y: Float, _ z: Float) -> SIMD3<Float> {
                    SIMD3(centerXZ.x, floorY, centerXZ.z) + basis * SIMD3(x, y, z)
                }
                let variant = Int(rng.next() % UInt64(nf))
                let isShop = variant % 2 == 0

                mb.box(nf + variant, origin: SIMD3(centerXZ.x, baseY, centerXZ.z), basis: basis,
                       size: SIMD3(width, floorY - baseY + groundH, depth), top: false, vOffset: baseY - floorY)
                mb.box(variant, origin: p(0, groundH, 0), basis: basis, size: SIMD3(width, height - groundH, depth),
                       top: !gabled, topSlot: sFlat)
                mb.box(sTrim, origin: p(0, groundH - 0.12, 0), basis: basis,
                       size: SIMD3(width + 0.24, 0.24, depth + 0.24))
                if gabled {
                    mb.box(sTrim, origin: p(0, height - 0.3, 0), basis: basis,
                           size: SIMD3(width + 0.3, 0.3, depth + 0.3))
                } else {
                    mb.box(sTrim, origin: p(0, height - 0.15, 0), basis: basis,
                           size: SIMD3(width + 0.5, 0.5, depth + 0.5), top: false)
                }

                // Upper floors: sills and hoods, or balconies with railings, aligned to the painted windows.
                let bays = Int(width / 3)
                let balconyPhase = rng.float() < 0.45 ? Int(rng.next() % 2) : -1
                let hoods = variant % 2 == 1
                for f in 1..<floors {
                    let by = groundH + Float(f - 1) * 3
                    for k in 0..<bays {
                        let x = -hx + 1.5 + Float(k) * 3
                        if balconyPhase >= 0 && k % 2 == balconyPhase {
                            mb.box(sTrim, origin: p(x, by - 0.04, hz + 0.5), basis: basis, size: SIMD3(2.3, 0.16, 1.0))
                            for t in 0...9 {
                                mb.box(sMetal, origin: p(x - 1.08 + Float(t) * 0.24, by + 0.12, hz + 0.96),
                                       basis: basis, size: SIMD3(0.035, 0.92, 0.035), top: false)
                            }
                            for sx: Float in [-1, 1] {
                                for t in 1...3 {
                                    mb.box(sMetal, origin: p(x + sx * 1.1, by + 0.12, hz + Float(t) * 0.24),
                                           basis: basis, size: SIMD3(0.035, 0.92, 0.035), top: false)
                                }
                                mb.box(sMetal, origin: p(x + sx * 1.1, by + 1.02, hz + 0.5), basis: basis,
                                       size: SIMD3(0.06, 0.06, 1.0))
                            }
                            mb.box(sMetal, origin: p(x, by + 1.02, hz + 0.98), basis: basis, size: SIMD3(2.26, 0.06, 0.07))
                        } else {
                            mb.box(sTrim, origin: p(x, by + 0.74, hz + 0.1), basis: basis, size: SIMD3(1.55, 0.1, 0.2))
                            if hoods {
                                mb.box(sTrim, origin: p(x, by + 2.5, hz + 0.07), basis: basis, size: SIMD3(1.6, 0.16, 0.14))
                            }
                        }
                    }
                }

                // Ground floor: steps up to each door, awnings over shop windows or canopies over doors.
                let frontGround = field.height(p(0, 0, hz + 1.2).x, p(0, 0, hz + 1.2).z)
                let rise = max(floorY - frontGround, 0.17)
                let steps = min(Int((rise / 0.17).rounded(.up)), 4)
                let stepH = rise / Float(steps)
                var tile: Float = 0
                while tile + 6 <= width + 0.01 {
                    let door = -hx + tile + 4.5
                    for i in 0..<steps {
                        let run = Float(steps - i) * 0.3
                        mb.box(sTrim, origin: p(door, frontGround - floorY - 0.3, hz + run / 2), basis: basis,
                               size: SIMD3(1.6, Float(i + 1) * stepH + 0.3, run))
                    }
                    if isShop {
                        let wx = -hx + tile + 1.5
                        let a = p(wx + 1.4, 2.82, hz), b = p(wx - 1.4, 2.82, hz)
                        let c = p(wx - 1.4, 2.3, hz + 1.2), d = p(wx + 1.4, 2.3, hz + 1.2)
                        mb.flatQuad(sAwning, a, b, c, d)
                    } else {
                        mb.box(sTrim, origin: p(door, 2.72, hz + 0.3), basis: basis, size: SIMD3(1.8, 0.12, 0.6))
                    }
                    tile += 6
                }

                // Drainpipes at the street corners.
                for sx: Float in [-1, 1] {
                    mb.box(sMetal, origin: p(sx * (hx - 0.18), baseY - floorY, hz + 0.08), basis: basis,
                           size: SIMD3(0.1, height - (baseY - floorY) - 0.3, 0.1), top: false)
                }

                if gabled {
                    let rise = depth * rng.float(0.28...0.42)
                    let rhx = hx + 0.35, rhz = hz + 0.5
                    let drop: Float = 0.5 * rise / hz
                    let roofSlot = rng.float() < 0.3 ? sSlate : sRoof
                    mb.flatQuad(roofSlot, p(-rhx, height - drop, rhz), p(rhx, height - drop, rhz),
                                p(rhx, height + rise, 0), p(-rhx, height + rise, 0))
                    mb.flatQuad(roofSlot, p(rhx, height - drop, -rhz), p(-rhx, height - drop, -rhz),
                                p(-rhx, height + rise, 0), p(rhx, height + rise, 0))
                    // Gable ends continue the upper facade texture.
                    for sx: Float in [-1, 1] {
                        let a = p(sx * hx, height, hz * sx), b = p(sx * hx, height, -hz * sx)
                        let top = p(sx * hx, height + rise, 0)
                        let nrm = basis * SIMD3(sx, 0, 0)
                        let v0 = height - groundH
                        let i0 = mb.vertex(a, nrm, SIMD2(0, v0)), i1 = mb.vertex(b, nrm, SIMD2(depth, v0))
                        let i2 = mb.vertex(top, nrm, SIMD2(depth / 2, v0 + rise * 0.3))
                        mb.triangle(variant, i0, i1, i2)
                    }
                    for _ in 0..<Int(rng.float(1...2.99)) {
                        let cx = rng.float((-hx + 1.2)...(hx - 1.2)), cz = rng.float(-0.3...0.3) * depth
                        mb.box(sTrim, origin: p(cx, height, cz), basis: basis, size: SIMD3(0.7, rise + 1.1, 0.9))
                        mb.box(sMetal, origin: p(cx, height + rise + 1.1, cz), basis: basis, size: SIMD3(0.9, 0.12, 1.1))
                    }
                } else {
                    mb.box(sMetal, origin: p(rng.float(-2...2), height, rng.float(-2...2)),
                           basis: basis, size: SIMD3(2.4, 1.4, 2.0))
                }
            }

            // Street lamps along the pavement.
            var lampArc = path.sample(at: range.lowerBound).arcLength + (side > 0 ? 0 : 12)
            while lampArc < endArc {
                let s = path.sample(at: Int(lampArc / path.totalLength * Float(path.stepCount)))
                lampArc += 24
                let rightH = simd_normalize(SIMD3(s.right.x, 0, s.right.z))
                let base = s.position + rightH * side * 11.2
                let ground = field.height(base.x, base.z)
                let basis = simd_float3x3(columns: (rightH, up, -s.forward))
                let foot = SIMD3(base.x, ground - 0.2, base.z)
                mb.box(sMetal, origin: foot, basis: basis, size: SIMD3(0.18, 6.6, 0.18))
                let armEnd = foot - rightH * side * 1.6 + up * 6.4
                mb.box(sMetal, origin: foot - rightH * side * 0.8 + up * 6.3, basis: basis,
                       size: SIMD3(1.7, 0.12, 0.12))
                mb.box(sGlass, origin: armEnd - up * 0.25, basis: basis, size: SIMD3(0.6, 0.25, 0.35))
            }
        }

        let node = SCNNode(geometry: mb.geometry(materials: materials))
        node.name = "town"
        return node
    }
}

@inline(__always) private func sgn(_ v: Float) -> Float { v < 0 ? -1 : 1 }

/// Separating-axis test for two convex quads.
private func rectsOverlap(_ a: [SIMD2<Float>], _ b: [SIMD2<Float>]) -> Bool {
    for poly in [a, b] {
        for i in 0..<4 {
            let e = poly[(i + 1) % 4] - poly[i]
            let axis = SIMD2(-e.y, e.x)
            let pa = a.map { simd_dot($0, axis) }, pb = b.map { simd_dot($0, axis) }
            if pa.max()! <= pb.min()! || pb.max()! <= pa.min()! { return false }
        }
    }
    return true
}
