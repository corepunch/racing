import SceneKit
import simd

/// Builds a faceted hover-ship from a `ShipDesign`. Nose points along −Z, the origin
/// is the centre of the hull at keel height.
enum ShipMesh {

    private enum Slot: Int, CaseIterable { case paint, accent, metal, glass, glow }

    /// Flat-shaded faces that always wind outward from a reference point.
    private struct Shell {
        var mesh = MeshBuilder(materialCount: Slot.allCases.count)

        mutating func tri(_ slot: Slot, _ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, from o: SIMD3<Float>) {
            var n = simd_cross(b - a, c - a)
            let length = simd_length(n)
            guard length > 1e-6 else { return }
            n /= length
            let outward = simd_dot(n, (a + b + c) / 3 - o) >= 0
            if !outward { n = -n }
            let i0 = mesh.vertex(a, n), i1 = mesh.vertex(b, n), i2 = mesh.vertex(c, n)
            if outward { mesh.triangle(slot.rawValue, i0, i1, i2) } else { mesh.triangle(slot.rawValue, i0, i2, i1) }
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
            let middle = centre(rings[rings.count / 2])
            for (ring, capSlot) in [(rings[0], slot), (rings[rings.count - 1], endCap ?? slot)] {
                let c = centre(ring)
                for k in 0..<ring.count { tri(capSlot, c, ring[k], ring[(k + 1) % ring.count], from: middle) }
            }
        }

        /// Thin tapered slab between a root edge and a tip edge (wings and fins).
        mutating func slab(_ slot: Slot, root: (SIMD3<Float>, SIMD3<Float>), tip: (SIMD3<Float>, SIMD3<Float>),
                           thickness: SIMD3<Float>) {
            let rings = [
                [root.0 - thickness, root.1 - thickness, root.1 + thickness, root.0 + thickness],
                [tip.0 - thickness * 0.4, tip.1 - thickness * 0.4, tip.1 + thickness * 0.4, tip.0 + thickness * 0.4],
            ]
            loft(slot, rings)
        }
    }

    /// Six-sided hull section: flat roof, chine at the widest point, narrower keel.
    private static func section(x: Float = 0, z: Float, halfWidth w: Float, top: Float, bottom: Float,
                                chine: Float = 0.45, roof: Float = 0.4) -> [SIMD3<Float>] {
        let yc = bottom + (top - bottom) * chine
        return [
            SIMD3(x - w * roof, top, z), SIMD3(x + w * roof, top, z), SIMD3(x + w, yc, z),
            SIMD3(x + w * 0.6, bottom, z), SIMD3(x - w * 0.6, bottom, z), SIMD3(x - w, yc, z),
        ]
    }

    /// A tapering body from nose to tail; `t` runs 0 (nose) to 1 (tail).
    private static func body(x: Float, length: Float, width: Float, height: Float, droop: Float,
                             nose: Float = 0.08, tail: Float = 0.7) -> [[SIMD3<Float>]] {
        let stations: [(t: Float, w: Float, h: Float)] = [
            (0, nose, 0.18), (0.14, 0.42, 0.42), (0.34, 0.8, 0.8), (0.55, 1, 1), (0.8, 0.92, 0.82), (1, tail, 0.6),
        ]
        return stations.map { s in
            let lift = -droop * (1 - s.t) * (1 - s.t) * 2
            return section(x: x, z: (s.t - 0.5) * length, halfWidth: width * s.w,
                           top: height * s.h + lift, bottom: -0.1 + lift * 0.5)
        }
    }

    static func build(_ design: ShipDesign) -> SCNNode {
        var shell = Shell()
        let L = design.length, W = design.width, H = design.height
        let tailZ = L / 2

        // Hull(s), and where the wings and engines attach.
        var wingRootX: Float
        var canopy: (z: Float, width: Float, base: Float)
        switch design.layout {
        case .dart:
            shell.loft(.paint, body(x: 0, length: L, width: W, height: H, droop: design.noseDroop))
            wingRootX = W * 0.85
            canopy = (-L * 0.08, W * 0.5, H * 0.9)
        case .twin:
            let offset = W * 0.95 + 0.25
            for side: Float in [-1, 1] {
                shell.loft(.paint, body(x: side * offset, length: L, width: W * 0.42, height: H * 0.7,
                                        droop: design.noseDroop, nose: 0.1, tail: 0.8))
            }
            // Central pod set back between the prows.
            let pod = body(x: 0, length: L * 0.62, width: W * 0.8, height: H, droop: 0, nose: 0.2, tail: 0.75)
                .map { $0.map { $0 + SIMD3(0, 0.05, L * 0.16) } }
            shell.loft(.accent, pod)
            // Bridge deck tying the three together.
            shell.loft(.metal, [
                section(z: -L * 0.05, halfWidth: offset, top: H * 0.34, bottom: 0.08, chine: 0.5, roof: 0.9),
                section(z: L * 0.38, halfWidth: offset, top: H * 0.38, bottom: 0.08, chine: 0.5, roof: 0.9),
            ])
            wingRootX = offset + W * 0.36
            canopy = (L * 0.1, W * 0.42, H * 0.95)
        case .manta:
            let stations: [(t: Float, w: Float, h: Float)] = [
                (0, 0.16, 0.2), (0.2, 0.75, 0.55), (0.5, 1.5, 0.9), (0.78, 1.75, 0.8), (1, 1.2, 0.5),
            ]
            shell.loft(.paint, stations.map { s in
                let lift = -design.noseDroop * (1 - s.t) * (1 - s.t) * 2
                return section(z: (s.t - 0.5) * L, halfWidth: W * s.w, top: H * 0.85 * s.h + lift,
                               bottom: -0.08 + lift * 0.5, chine: 0.35, roof: 0.3)
            })
            wingRootX = W * 1.5
            canopy = (-L * 0.02, W * 0.48, H * 0.66)
        }

        // Canopy: a low glass blister.
        let cz = canopy.z, cw = canopy.width, cb = canopy.base
        shell.loft(.glass, [
            section(z: cz - L * 0.16, halfWidth: cw * 0.35, top: cb + 0.02, bottom: cb - 0.12),
            section(z: cz - L * 0.04, halfWidth: cw, top: cb + 0.26, bottom: cb - 0.12),
            section(z: cz + L * 0.1, halfWidth: cw * 0.85, top: cb + 0.22, bottom: cb - 0.12),
            section(z: cz + L * 0.2, halfWidth: cw * 0.3, top: cb + 0.06, bottom: cb - 0.12),
        ])

        // Wings: swept slabs with accent tips.
        let chord = L * 0.34
        let rootZ = L * 0.12
        let sweep = design.wingSweep * design.wingSpan
        for side: Float in [-1, 1] {
            let root = (SIMD3(side * wingRootX, 0.16, rootZ - chord / 2), SIMD3(side * wingRootX, 0.16, rootZ + chord / 2))
            let tipX = side * (wingRootX + design.wingSpan)
            let tip = (SIMD3(tipX, 0.06, rootZ + sweep - chord * 0.1), SIMD3(tipX, 0.06, rootZ + sweep + chord * 0.32))
            shell.slab(.paint, root: root, tip: tip, thickness: SIMD3(0, 0.07, 0))
            // Tip rail.
            let out = SIMD3<Float>(side * 0.14, 0, 0)
            shell.slab(.accent, root: (tip.0 - SIMD3(0, 0, 0.25), tip.1 + SIMD3(0, 0, 0.3)),
                       tip: (tip.0 + out, tip.1 + out + SIMD3(0, 0, 0.2)), thickness: SIMD3(0, 0.11, 0))
        }

        // Tail fins.
        let finX: [Float] = design.finCount == 2 ? [-W * 0.75, W * 0.75] : (design.finCount == 1 ? [0] : [])
        for x in finX {
            let lean = x == 0 ? 0 : (x > 0 ? 0.28 : -0.28) * design.finHeight
            let baseY = design.layout == .manta ? H * 0.5 : H * 0.62
            shell.slab(.accent,
                       root: (SIMD3(x, baseY, tailZ - L * 0.3), SIMD3(x, baseY, tailZ - 0.05)),
                       tip: (SIMD3(x + lean, baseY + design.finHeight, tailZ - L * 0.08),
                             SIMD3(x + lean, baseY + design.finHeight, tailZ + 0.18)),
                       thickness: SIMD3(0.045, 0, 0))
        }

        // Engines: dark nacelles with a glowing exhaust face.
        let r = design.engineRadius
        var engineX: [Float]
        switch design.engineCount {
        case 1: engineX = [0]
        case 2: engineX = [-wingRootX * 0.62, wingRootX * 0.62]
        default: engineX = [-wingRootX * 0.78, 0, wingRootX * 0.78]
        }
        if design.layout == .twin, design.engineCount == 2 { engineX = [-(W * 0.95 + 0.25), W * 0.95 + 0.25] }
        var exhausts: [SIMD3<Float>] = []
        for x in engineX {
            let y = design.layout == .manta ? H * 0.36 : H * 0.34
            func ring(_ z: Float, _ radius: Float) -> [SIMD3<Float>] {
                (0..<8).map { k in
                    let a = (Float(k) + 0.5) / 8 * 2 * .pi
                    return SIMD3(x + cos(a) * radius, y + sin(a) * radius, z)
                }
            }
            shell.loft(.metal, [ring(tailZ - L * 0.3, r * 0.7), ring(tailZ - L * 0.1, r * 1.12), ring(tailZ + 0.22, r)],
                       endCap: .glow)
            exhausts.append(SIMD3(x, y, tailZ + 0.23))
        }

        let node = SCNNode(geometry: shell.mesh.geometry(materials: materials(design)))
        node.name = "hull"

        // Exhaust plumes: additive cones the game stretches with thrust.
        let flames = SCNNode()
        flames.name = "flames"
        let plume = SCNMaterial()
        plume.lightingModel = .constant
        plume.diffuse.contents = UIColor.black
        plume.emission.contents = color(design.glow)
        plume.emission.intensity = 2.4
        plume.blendMode = .add
        plume.writesToDepthBuffer = false
        plume.isDoubleSided = true
        for e in exhausts {
            let cone = SCNCone(topRadius: 0, bottomRadius: CGFloat(r * 0.72), height: 1)
            cone.radialSegmentCount = 8
            cone.firstMaterial = plume
            let flame = SCNNode(geometry: cone)
            // Cone points along +Z (backwards), base on the exhaust; pivot at the base so scaling stretches it.
            flame.pivot = SCNMatrix4MakeTranslation(0, -0.5, 0)
            flame.eulerAngles = SCNVector3(Float.pi / 2, 0, 0)
            flame.simdPosition = e
            flame.castsShadow = false
            flames.addChildNode(flame)
        }
        let root = SCNNode()
        root.addChildNode(node)
        root.addChildNode(flames)
        return root
    }

    /// Stretches the exhaust plumes: 0 idle, 1 flat out, above 1 on boost.
    static func setThrust(_ amount: Float, on ship: SCNNode) {
        guard let flames = ship.childNode(withName: "flames", recursively: true) else { return }
        let length = 0.3 + 1.5 * amount
        for flame in flames.childNodes { flame.simdScale = SIMD3(1, length, 1) }
    }

    private static func color(_ c: SIMD3<Float>) -> UIColor {
        UIColor(red: CGFloat(c.x), green: CGFloat(c.y), blue: CGFloat(c.z), alpha: 1)
    }

    private static func materials(_ design: ShipDesign) -> [SCNMaterial] {
        func pbr(_ c: SIMD3<Float>, metal: CGFloat, rough: CGFloat, emit: CGFloat = 0) -> SCNMaterial {
            let m = SCNMaterial()
            m.lightingModel = .physicallyBased
            m.diffuse.contents = color(c)
            m.metalness.contents = metal
            m.roughness.contents = rough
            if emit > 0 {
                m.emission.contents = color(c)
                m.emission.intensity = emit
            }
            return m
        }
        let glow = SCNMaterial()
        glow.lightingModel = .constant
        glow.diffuse.contents = UIColor.black
        glow.emission.contents = color(design.glow)
        glow.emission.intensity = 3
        return [
            pbr(design.primary, metal: 0.55, rough: 0.32, emit: 0.12),
            pbr(design.accent, metal: 0.3, rough: 0.4, emit: 0.55),
            pbr(SIMD3(0.09, 0.1, 0.12), metal: 0.9, rough: 0.45),
            pbr(SIMD3(0.03, 0.05, 0.08), metal: 1, rough: 0.08),
            glow,
        ]
    }
}
