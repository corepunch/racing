import SceneKit
import simd

/// A built car: the chassis node and its four wheel nodes (front-left, front-right,
/// rear-left, rear-right), which are direct children so the vehicle physics can drive them.
struct CarModel {
    let node: SCNNode
    let wheels: [SCNNode]
    let radii: [Float]
}

/// Builds a faceted open-wheel racer from a `CarDesign`. Nose points along −Z. The node's
/// origin is `axleHeight` above the road, between the axles.
enum CarMesh {

    /// Height of the chassis origin above the road when the car sits level.
    static let axleHeight: Float = 0.42
    /// Underside of the bodywork above the road.
    private static let clearance: Float = 0.3

    enum Slot: Int, CaseIterable { case paint, accent, metal, glass, glow }

    /// Flat-shaded faces that always wind outward from a reference point.
    struct Shell {
        var mesh = MeshBuilder(materialCount: Slot.allCases.count)
        /// Where this shell sits on the car, so textures run on from one part to the next.
        var origin = SIMD3<Float>.zero
        /// Replaces the bodywork projection: texture coordinates for a point, given its face's
        /// normal and centre.
        var mapping: ((_ p: SIMD3<Float>, _ n: SIMD3<Float>, _ centre: SIMD3<Float>) -> SIMD2<Float>)?

        /// The finished surface: gentle bends shade as curves, edges sharper than 37° stay crisp.
        func geometry(materials: [SCNMaterial]) -> SCNGeometry {
            var smooth = mesh
            smooth.smoothNormals()
            return smooth.geometry(materials: materials)
        }

        mutating func tri(_ slot: Slot, _ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, from o: SIMD3<Float>) {
            var n = simd_cross(b - a, c - a)
            let length = simd_length(n)
            guard length > 1e-6 else { return }
            n /= length
            let outward = simd_dot(n, (a + b + c) / 3 - o) >= 0
            if !outward { n = -n }
            let centre = (a + b + c) / 3
            func map(_ p: SIMD3<Float>) -> SIMD2<Float> { mapping?(p, n, centre) ?? uv(p, n) }
            let i0 = mesh.vertex(a, n, map(a)), i1 = mesh.vertex(b, n, map(b)), i2 = mesh.vertex(c, n, map(c))
            if outward { mesh.triangle(slot.rawValue, i0, i1, i2) } else { mesh.triangle(slot.rawValue, i0, i2, i1) }
        }

        /// Box projection in metres onto the layout the car textures share: decks by distance
        /// from the centre line, flanks by height, both by position along the car, so a seam
        /// across the deck carries on down the flank. A shoulder counts as flank once it is
        /// steeper than 30 degrees, because that is where a side graphic belongs.
        private func uv(_ p: SIMD3<Float>, _ n: SIMD3<Float>) -> SIMD2<Float> {
            let q = p + origin, m = abs(n)
            if m.x > 0.5 && m.x >= m.z { return SIMD2(ProceduralTextures.carFlank + q.y, q.z) }
            return m.z > m.y ? SIMD2(q.x, q.y) : SIMD2(q.x, q.z)
        }

        mutating func quad(_ slot: Slot, _ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, _ d: SIMD3<Float>,
                           from o: SIMD3<Float>) {
            tri(slot, a, b, c, from: o)
            tri(slot, a, c, d, from: o)
        }

        /// Skins consecutive rings (same point count) and caps both ends.
        mutating func loft(_ slot: Slot, _ rings: [[SIMD3<Float>]], endCap: Slot? = nil) {
            func centre(_ r: [SIMD3<Float>]) -> SIMD3<Float> { r.reduce(.zero, +) / Float(r.count) }
            for i in 0..<(rings.count - 1) {
                let a = rings[i], b = rings[i + 1]
                let o = (centre(a) + centre(b)) / 2
                for k in 0..<a.count {
                    let k1 = (k + 1) % a.count
                    quad(slot, a[k], a[k1], b[k1], b[k], from: o)
                }
            }
            let last = rings.count - 1
            for (ring, adjacent, capSlot) in [(rings[0], rings[1], slot),
                                              (rings[last], rings[last - 1], endCap ?? slot)] {
                let c = centre(ring)
                let inside = (c + centre(adjacent)) / 2
                for k in 0..<ring.count { tri(capSlot, c, ring[k], ring[(k + 1) % ring.count], from: inside) }
            }
        }

        /// Thin tapered slab between a root edge and a tip edge (suspension arms, struts).
        mutating func slab(_ slot: Slot, root: (SIMD3<Float>, SIMD3<Float>), tip: (SIMD3<Float>, SIMD3<Float>),
                           thickness: SIMD3<Float>) {
            loft(slot, [
                [root.0 - thickness, root.1 - thickness, root.1 + thickness, root.0 + thickness],
                [tip.0 - thickness * 0.6, tip.1 - thickness * 0.6, tip.1 + thickness * 0.6, tip.0 + thickness * 0.6],
            ])
        }

        mutating func box(_ slot: Slot, centre c: SIMD3<Float>, size: SIMD3<Float>) {
            let h = size / 2
            func ring(_ z: Float) -> [SIMD3<Float>] {
                [SIMD3(c.x - h.x, c.y - h.y, z), SIMD3(c.x + h.x, c.y - h.y, z),
                 SIMD3(c.x + h.x, c.y + h.y, z), SIMD3(c.x - h.x, c.y + h.y, z)]
            }
            loft(slot, [ring(c.z - h.z), ring(c.z + h.z)])
        }
    }

    /// Six-sided body section: flat roof, chine at the widest point, narrower floor.
    static func section(x: Float = 0, z: Float, halfWidth w: Float, top: Float, bottom: Float = clearance,
                                chine: Float = 0.45, roof: Float = 0.4) -> [SIMD3<Float>] {
        let yc = bottom + (top - bottom) * chine
        return [
            SIMD3(x - w * roof, top, z), SIMD3(x + w * roof, top, z), SIMD3(x + w, yc, z),
            SIMD3(x + w * 0.7, bottom, z), SIMD3(x - w * 0.7, bottom, z), SIMD3(x - w, yc, z),
        ]
    }

    /// A body lofted through `stations`: `t` runs 0 (nose) to 1 (tail), `w` and `h` scale width and height.
    private static func body(x: Float = 0, from z0: Float, to z1: Float, width: Float, height: Float,
                             _ stations: [(t: Float, w: Float, h: Float)], roof: Float = 0.4) -> [[SIMD3<Float>]] {
        stations.map { s in
            section(x: x, z: z0 + (z1 - z0) * s.t, halfWidth: width * s.w,
                    top: clearance + (height - clearance) * s.h, roof: roof)
        }
    }

    static func build(_ design: CarDesign) -> CarModel {
        if let garage = design.garage { return GarageMesh.build(garage, glow: design.glow) }
        var shell = Shell()
        let L = design.length, W = design.width, H = design.height
        let noseZ = -L / 2, tailZ = L / 2
        let tub: [(t: Float, w: Float, h: Float)] = [
            (0, 0.14, 0.2), (0.16, 0.4, 0.38), (0.4, 0.82, 0.8), (0.55, 1, 1), (0.8, 0.92, 0.82), (1, 0.72, 0.55),
        ]

        // Bodywork, and where the suspension arms, canopy and exhausts attach.
        var armX: Float
        var canopy: (z: Float, width: Float, base: Float)
        switch design.layout {
        case .formula:
            let core = W * 0.6
            shell.loft(.paint, body(from: noseZ, to: tailZ, width: core, height: H, tub))
            for side: Float in [-1, 1] {
                shell.loft(.accent, body(x: side * (core + W * 0.2), from: -L * 0.1, to: L * 0.34, width: W * 0.36,
                                         height: H * 0.62, [(0, 0.5, 0.5), (0.25, 1, 1), (0.8, 1, 0.9), (1, 0.6, 0.6)]))
            }
            armX = core * 0.8
            canopy = (L * 0.02, core * 0.62, H * 0.93)
        case .wedge:
            shell.loft(.paint, body(from: noseZ, to: tailZ, width: W, height: H, [
                (0, 0.6, 0.12), (0.22, 0.9, 0.34), (0.5, 1, 0.92), (0.78, 1, 0.9), (1, 0.9, 0.62),
            ], roof: 0.55))
            // Side skirts.
            for side: Float in [-1, 1] {
                shell.box(.accent, centre: SIMD3(side * W, clearance + 0.09, L * 0.04), size: SIMD3(0.08, 0.14, L * 0.36))
            }
            armX = W * 0.85
            canopy = (L * 0.04, W * 0.5, H * 0.9)
        case .twin:
            let offset = W * 0.68
            for side: Float in [-1, 1] {
                shell.loft(.paint, body(x: side * offset, from: noseZ, to: tailZ, width: W * 0.3, height: H * 0.62, [
                    (0, 0.3, 0.3), (0.2, 0.8, 0.7), (0.5, 1, 1), (0.8, 1, 0.9), (1, 0.8, 0.7),
                ]))
            }
            shell.loft(.accent, body(from: -L * 0.16, to: L * 0.42, width: W * 0.46, height: H, [
                (0, 0.3, 0.45), (0.3, 0.9, 0.95), (0.6, 1, 1), (1, 0.75, 0.6),
            ]))
            // Deck tying the three together.
            shell.loft(.metal, [
                section(z: -L * 0.12, halfWidth: offset, top: clearance + 0.2, chine: 0.5, roof: 0.9),
                section(z: L * 0.4, halfWidth: offset, top: clearance + 0.24, chine: 0.5, roof: 0.9),
            ])
            armX = W * 0.9
            canopy = (L * 0.1, W * 0.3, H * 0.95)
        }

        // Canopy: a low glass blister.
        let cz = canopy.z, cw = canopy.width, cb = canopy.base
        shell.loft(.glass, [
            section(z: cz - L * 0.15, halfWidth: cw * 0.4, top: cb + 0.02, bottom: cb - 0.14),
            section(z: cz - L * 0.04, halfWidth: cw, top: cb + 0.2, bottom: cb - 0.14),
            section(z: cz + L * 0.08, halfWidth: cw * 0.9, top: cb + 0.18, bottom: cb - 0.14),
            section(z: cz + L * 0.17, halfWidth: cw * 0.35, top: cb + 0.05, bottom: cb - 0.14),
        ])

        // Front wing with end plates, low on the nose.
        let frontSpan = design.halfWidth * (0.7 + 0.28 * design.wing)
        let frontChord = 0.3 + 0.22 * design.wing
        shell.box(.paint, centre: SIMD3(0, 0.25, noseZ + frontChord / 2 - 0.05), size: SIMD3(frontSpan * 2, 0.05, frontChord))
        for side: Float in [-1, 1] {
            shell.box(.accent, centre: SIMD3(side * frontSpan, 0.32, noseZ + frontChord / 2 - 0.05),
                      size: SIMD3(0.05, 0.2, frontChord + 0.1))
        }

        // Rear wing on two struts.
        let rearSpan = design.track * 0.92
        let rearChord = 0.36 + 0.3 * design.wing
        let wingY = H + 0.2 + 0.22 * design.wing
        let wingZ = tailZ - 0.1
        shell.box(.accent, centre: SIMD3(0, wingY, wingZ), size: SIMD3(rearSpan * 2, 0.06, rearChord))
        for side: Float in [-1, 1] {
            shell.box(.paint, centre: SIMD3(side * rearSpan, wingY - 0.06, wingZ), size: SIMD3(0.05, 0.3, rearChord + 0.12))
            let strutX = side * min(W * 0.5, rearSpan * 0.5)
            shell.slab(.metal,
                       root: (SIMD3(strutX, H * 0.6, wingZ - 0.35), SIMD3(strutX, H * 0.6, wingZ - 0.05)),
                       tip: (SIMD3(strutX, wingY, wingZ - 0.12), SIMD3(strutX, wingY, wingZ + 0.1)),
                       thickness: SIMD3(0.03, 0, 0))
        }

        // Wheels and the arms that carry them.
        let places: [(x: Float, z: Float, r: Float)] = [
            (-design.track, -design.axle, design.frontRadius), (design.track, -design.axle, design.frontRadius),
            (-design.track, design.axle, design.rearRadius), (design.track, design.axle, design.rearRadius),
        ]
        for p in places {
            let side: Float = p.x > 0 ? 1 : -1
            let hub = side * (design.track - design.tyreWidth / 2)
            for (lead, y) in [(Float(-0.22), Float(0.5)), (0.22, 0.42)] {
                shell.slab(.metal,
                           root: (SIMD3(side * armX, y, p.z + lead - 0.09), SIMD3(side * armX, y, p.z + lead + 0.09)),
                           tip: (SIMD3(hub, p.r, p.z - 0.05), SIMD3(hub, p.r, p.z + 0.05)),
                           thickness: SIMD3(0, 0.03, 0))
            }
        }

        // Exhausts: dark nozzles with a glowing face.
        let r = design.engineRadius
        let spread = min(W * 0.62, 0.62)
        let engineX: [Float]
        switch design.engineCount {
        case 1: engineX = [0]
        case 2: engineX = [-spread, spread]
        default: engineX = [-spread, 0, spread]
        }
        var exhausts: [SIMD3<Float>] = []
        for x in engineX {
            let y = clearance + (H - clearance) * 0.42
            func ring(_ z: Float, _ radius: Float) -> [SIMD3<Float>] {
                (0..<8).map { k in
                    let a = (Float(k) + 0.5) / 8 * 2 * .pi
                    return SIMD3(x + cos(a) * radius, y + sin(a) * radius, z)
                }
            }
            shell.loft(.metal, [ring(tailZ - 0.55, r * 0.75), ring(tailZ - 0.1, r * 1.1), ring(tailZ + 0.2, r)], endCap: .glow)
            exhausts.append(SIMD3(x, y, tailZ + 0.21))
        }

        let mats = materials(design)
        let chassis = SCNNode()
        // Everything above was modelled with the road at y = 0.
        let lower = SIMD3<Float>(0, -axleHeight, 0)
        let hull = SCNNode(geometry: shell.geometry(materials: mats))
        hull.name = "hull"
        hull.simdPosition = lower
        chassis.addChildNode(hull)

        // Afterburner plumes: additive cones the game stretches with thrust.
        let flames = makeFlames(exhausts.map { ($0, r) }, glow: design.glow)
        flames.simdPosition = lower
        chassis.addChildNode(flames)

        let rim = materials(paint: design.primary, accent: design.accent, light: design.glow,
                            detailed: false)[Slot.accent.rawValue]
        let wheels = places.map { p -> SCNNode in
            let wheel = makeWheel(radius: p.r, width: design.tyreWidth, rim: rim)
            wheel.simdPosition = SIMD3(p.x, p.r, p.z) + lower
            chassis.addChildNode(wheel)
            return wheel
        }
        return CarModel(node: chassis, wheels: wheels, radii: places.map(\.r))
    }

    static func makeFlames(_ exhausts: [(SIMD3<Float>, Float)], glow: SIMD3<Float>) -> SCNNode {
        let flames = SCNNode()
        flames.name = "flames"
        let plume = SCNMaterial()
        plume.lightingModel = .constant
        plume.diffuse.contents = UIColor.black
        plume.emission.contents = color(glow)
        plume.emission.intensity = 2.4
        plume.blendMode = .add
        plume.writesToDepthBuffer = false
        plume.isDoubleSided = true
        for (position, radius) in exhausts {
            let cone = SCNCone(topRadius: 0, bottomRadius: CGFloat(radius * 0.72), height: 1)
            cone.radialSegmentCount = 8
            cone.firstMaterial = plume
            let flame = SCNNode(geometry: cone)
            // Cone points backwards with its base on the exhaust; the pivot makes scaling stretch it.
            flame.pivot = SCNMatrix4MakeTranslation(0, -0.5, 0)
            flame.eulerAngles = SCNVector3(Float.pi / 2, 0, 0)
            flame.simdPosition = position
            flame.castsShadow = false
            flames.addChildNode(flame)
        }
        return flames
    }

    /// A fat slick on a bright rim. The carrier node is what the physics turns; a dark
    /// bar across the rim makes the spin visible.
    private static func makeWheel(radius: Float, width: Float, rim: SCNMaterial) -> SCNNode {
        let dark = SCNMaterial()
        dark.lightingModel = .physicallyBased
        dark.diffuse.contents = UIColor(white: 0.1, alpha: 1)
        dark.metalness.contents = 0.9
        dark.roughness.contents = 0.4

        let carrier = SCNNode()
        let tyre = SCNCylinder(radius: CGFloat(radius), height: CGFloat(width))
        tyre.radialSegmentCount = 24
        tyre.materials = [rubber(treadAround: radius), rubber(), rubber()]
        let tyreNode = SCNNode(geometry: tyre)
        tyreNode.eulerAngles = SCNVector3(0, 0, Float.pi / 2)
        carrier.addChildNode(tyreNode)

        let hub = SCNCylinder(radius: CGFloat(radius * 0.64), height: CGFloat(width + 0.03))
        hub.radialSegmentCount = 12
        hub.materials = [dark, rim, rim]
        let hubNode = SCNNode(geometry: hub)
        hubNode.eulerAngles = tyreNode.eulerAngles
        carrier.addChildNode(hubNode)

        let bar = SCNBox(width: CGFloat(width + 0.06), height: CGFloat(radius * 1.2), length: 0.09, chamferRadius: 0)
        bar.firstMaterial = dark
        carrier.addChildNode(SCNNode(geometry: bar))
        return carrier
    }

    /// Tyre rubber: dull, never metallic. `treadAround` a wheel of that radius cuts a tread into
    /// it, for surfaces mapped once round the wheel and once across it.
    static func rubber(treadAround radius: Float? = nil) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = UIColor(white: 0.075, alpha: 1)
        m.roughness.contents = 0.82
        m.metalness.contents = 0
        if let radius {
            let blocks = (2 * Float.pi * radius / 0.13).rounded()
            ProceduralTextures.tyreTread.overlay(on: m, tile: SIMD2(1 / blocks, 1))
        }
        return m
    }

    /// Sets the afterburners: 0 idle, 1 flat out, above 1 on boost.
    static func setThrust(_ amount: Float, on car: SCNNode) {
        if let flames = car.childNode(withName: "flames", recursively: false) {
            let length = 0.12 + 1.15 * amount
            let girth = 0.75 + 0.3 * min(amount, 1.6)
            for flame in flames.childNodes { flame.simdScale = SIMD3(girth, length, girth) }
        }
    }

    static func color(_ c: SIMD3<Float>) -> UIColor {
        UIColor(red: CGFloat(c.x), green: CGFloat(c.y), blue: CGFloat(c.z), alpha: 1)
    }

    private static func materials(_ design: CarDesign) -> [SCNMaterial] {
        materials(paint: design.primary, accent: design.accent, light: design.glow,
                  livery: (design.accent, Int(design.seed % UInt64(ProceduralTextures.carLiveryStyles))))
    }

    /// `detailed` lays panel seams, vents and wear over the paint, and `livery` paints racing
    /// graphics on it in a second colour. Shells carry the UVs for both; anything else (a rim
    /// on a stock cylinder) wants the plain colours.
    static func materials(paint: SIMD3<Float>, accent: SIMD3<Float>, light: SIMD3<Float>, detailed: Bool = true,
                          livery: (color: SIMD3<Float>, style: Int)? = nil) -> [SCNMaterial] {
        /// `coat` lacquers the surface: a second, mirror-sharp highlight over the paint.
        func pbr(_ c: SIMD3<Float>, metal: CGFloat, rough: CGFloat, coat: Bool = false,
                 detail: TextureSet? = nil) -> SCNMaterial {
            let m = SCNMaterial()
            m.lightingModel = .physicallyBased
            m.diffuse.contents = color(c)
            m.metalness.contents = metal
            m.roughness.contents = rough
            if coat {
                m.clearCoat.contents = 1.0
                m.clearCoatRoughness.contents = 0.18
            }
            if detailed { detail?.overlay(on: m, tile: ProceduralTextures.carTile) }
            return m
        }
        let body = pbr(paint, metal: 0.7, rough: 0.32, coat: true, detail: ProceduralTextures.carPanels)
        if detailed, let livery {
            body.diffuse.contents = ProceduralTextures.carLivery(paint: paint, graphics: livery.color, style: livery.style)
        }
        let glow = SCNMaterial()
        glow.lightingModel = .constant
        glow.diffuse.contents = UIColor.black
        glow.emission.contents = color(light)
        glow.emission.intensity = 3
        // Bodywork only reflects light; the glow strips and plumes are the car's only emitters.
        return [
            body,
            pbr(accent, metal: 0.5, rough: 0.4, coat: true, detail: ProceduralTextures.carPanels),
            pbr(SIMD3(0.09, 0.1, 0.12), metal: 0.9, rough: 0.45, detail: ProceduralTextures.carMetal),
            pbr(SIMD3(0.03, 0.05, 0.08), metal: 1, rough: 0.08),
            glow,
        ]
    }
}
