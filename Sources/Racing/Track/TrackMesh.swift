import SceneKit
import simd

/// Builds the track ribbon SCNNode by sweeping a cross-section profile
/// along all PathSamples.  Separate sub-nodes are added for kerbs and shoulders
/// so materials can be swapped independently.
final class TrackMeshBuilder {

    // Cross-section profile: (offsetRight m, heightUp m, materialSlot)
    // Slots: 0 = asphalt, 1 = kerb (alternating red/white), 2 = gravel shoulder, 3 = terrain
    private static let profile: [(x: Float, y: Float, slot: Int)] = [
        (-16.0, -0.4, 3),   // outer terrain
        (-12.0, -0.4, 3),
        (-12.0,  0.0, 3),
        (-10.0,  0.0, 2),   // gravel shoulder L
        ( -7.5,  0.0, 2),
        ( -7.5,  0.0, 1),   // kerb L outer
        ( -5.5,  0.14, 1),  // kerb L inner (raised)
        ( -5.5,  0.0, 0),   // asphalt L edge
        (  0.0,  0.0, 0),   // asphalt centre
        (  5.5,  0.0, 0),   // asphalt R edge
        (  5.5,  0.14, 1),  // kerb R inner
        (  7.5,  0.0, 1),   // kerb R outer
        (  7.5,  0.0, 2),   // gravel shoulder R
        ( 10.0,  0.0, 2),
        ( 12.0,  0.0, 3),   // terrain R
        ( 12.0, -0.4, 3),
        ( 16.0, -0.4, 3),
    ]

    static func buildTrackNode(path: TrackPath) -> SCNNode {
        let root = SCNNode()
        root.name = "trackRoot"

        let (geo, physGeo) = buildGeometry(path: path)
        let trackNode = SCNNode(geometry: geo)
        trackNode.name = "trackMesh"

        // Static concave physics mesh so the car can collide with the edges
        trackNode.physicsBody = SCNPhysicsBody(
            type: .static,
            shape: SCNPhysicsShape(
                geometry: physGeo,
                options: [.type: SCNPhysicsShape.ShapeType.concavePolyhedron]
            )
        )
        trackNode.physicsBody?.categoryBitMask  = PhysicsCategory.track
        trackNode.physicsBody?.collisionBitMask = PhysicsCategory.car

        root.addChildNode(trackNode)
        return root
    }

    // MARK: - Geometry builder

    // Material slot assigned per profile strip (by left vertex slot)
    private static func slotForStrip(_ pi: Int) -> Int {
        profile[pi].slot
    }

    private static func buildGeometry(path: TrackPath) -> (SCNGeometry, SCNGeometry) {
        let samples = path.samples
        let n = samples.count
        let p = profile.count

        var positions  = [SCNVector3]()
        var normals    = [SCNVector3]()
        var texcoords  = [CGPoint]()

        positions.reserveCapacity(n * p)
        normals.reserveCapacity(n * p)
        texcoords.reserveCapacity(n * p)

        for s in samples {
            let v = CGFloat(s.arcLength / 8.0)
            for prof in profile {
                let offset = s.right * prof.x + s.up * prof.y
                let pos    = s.position + offset
                positions.append(SCNVector3(pos.x, pos.y, pos.z))
                normals.append(SCNVector3(s.up.x, s.up.y, s.up.z))
                texcoords.append(CGPoint(x: CGFloat(prof.x / 16.0 + 0.5), y: v))
            }
        }

        // Build separate index arrays per material slot (0..3)
        let slotCount = 4
        var slotIndices: [[Int32]] = Array(repeating: [], count: slotCount)

        for si in 0..<n {
            let ni = (si + 1) % n
            for pi in 0..<(p - 1) {
                let a = Int32(si * p + pi)
                let b = Int32(si * p + pi + 1)
                let c = Int32(ni * p + pi)
                let d = Int32(ni * p + pi + 1)
                let slot = slotForStrip(pi)
                slotIndices[slot].append(contentsOf: [a, c, b, b, c, d])
            }
        }

        let posSource = SCNGeometrySource(vertices: positions)
        let nrmSource = SCNGeometrySource(normals: normals)
        let uvSource  = SCNGeometrySource(textureCoordinates: texcoords)

        // One SCNGeometryElement per material slot
        let elements = slotIndices.map { idxs in
            SCNGeometryElement(indices: idxs, primitiveType: .triangles)
        }

        let geo = SCNGeometry(sources: [posSource, nrmSource, uvSource], elements: elements)

        // Assign materials in slot order
        geo.materials = makeMaterials()

        // Physics uses the full mesh
        let allIndices = slotIndices.flatMap { $0 }
        let physElement = SCNGeometryElement(indices: allIndices, primitiveType: .triangles)
        let physGeo = SCNGeometry(sources: [posSource], elements: [physElement])

        return (geo, physGeo)
    }

    // MARK: - Materials (one per slot: 0=asphalt, 1=kerb, 2=gravel shoulder, 3=terrain)

    private static func makeMaterials() -> [SCNMaterial] {
        let asphalt = SCNMaterial()
        asphalt.diffuse.contents   = UIColor(white: 0.22, alpha: 1)
        asphalt.roughness.contents = 0.85
        asphalt.isDoubleSided      = true

        let kerb = SCNMaterial()
        kerb.diffuse.contents      = UIColor(red: 0.85, green: 0.15, blue: 0.15, alpha: 1)
        kerb.roughness.contents    = 0.7
        kerb.isDoubleSided         = true

        let shoulder = SCNMaterial()
        shoulder.diffuse.contents  = UIColor(red: 0.60, green: 0.50, blue: 0.35, alpha: 1)
        shoulder.roughness.contents = 1.0
        shoulder.isDoubleSided     = true

        let terrain = SCNMaterial()
        terrain.diffuse.contents   = UIColor(red: 0.45, green: 0.55, blue: 0.30, alpha: 1)
        terrain.roughness.contents = 1.0
        terrain.isDoubleSided      = true

        return [asphalt, kerb, shoulder, terrain]
    }
}

// MARK: - Track decorations — all Kenney assets, no procedural geometry

final class TrackDecorations {

    private static var templates: [String: SCNNode] = [:]

    // Loads from Props/ (OBJ) first, then Decorations/ (USDZ) as fallback.
    private static func loadTemplate(_ name: String, scale: Float = 1) -> SCNNode? {
        let key = "\(name)@\(scale)"
        if let t = templates[key] { return t }

        let url: URL?
        if let u = Bundle.main.url(forResource: name, withExtension: "obj",
                                    subdirectory: "Props") {
            url = u
        } else if let u = Bundle.main.url(forResource: name, withExtension: "usdz",
                                           subdirectory: "Decorations") {
            url = u
        } else {
            return nil
        }
        guard let u = url, let scene = try? SCNScene(url: u, options: nil) else { return nil }
        let root = scene.rootNode
        if scale != 1 { root.simdScale = SIMD3<Float>(repeating: scale) }
        templates[key] = root
        return root
    }

    // MARK: - Public entry point

    static func addDecorations(to parentNode: SCNNode, path: TrackPath) {
        let samples = path.samples
        let count   = samples.count

        // Start/finish gantry at sample 0
        placeAlongTrack("overhead", scale: 11, parent: parentNode,
                        sample: samples[0], sideOffset: 0, facingForward: true)
        // Checkered flags flanking start
        placeAlongTrack("flagCheckers", scale: 7, parent: parentNode,
                        sample: samples[0], sideOffset:  7)
        placeAlongTrack("flagCheckers", scale: 7, parent: parentNode,
                        sample: samples[0], sideOffset: -7)

        // Barriers along kerb edges every 4 samples (barrierRed is 0.12 m at scale 7 → ~0.84 m/instance)
        for i in stride(from: 0, to: count, by: 4) {
            let s = samples[i]
            placeAlongTrack("barrierRed", scale: 7, parent: parentNode,
                            sample: s, sideOffset:  s.halfWidth + 2.5, facingForward: true)
            placeAlongTrack("barrierRed", scale: 7, parent: parentNode,
                            sample: s, sideOffset: -(s.halfWidth + 2.5), facingForward: true)
        }

        // Kenney lightPostLarge every 10 samples (0.796 m tall × 8 = 6.4 m)
        for i in stride(from: 0, to: count, by: 10) {
            let s = samples[i]
            placeAlongTrack("lightPostLarge", scale: 8, parent: parentNode,
                            sample: s, sideOffset:  s.halfWidth + 1.5)
            placeAlongTrack("lightPostLarge", scale: 8, parent: parentNode,
                            sample: s, sideOffset: -(s.halfWidth + 1.5))
        }

        // Grandstands every 40 samples; trees fill alternate gaps — start at 20 to clear the start box
        for i in stride(from: 20, to: count, by: 20) {
            let s    = samples[i]
            let slot = (i - 20) / 20
            if slot % 3 == 2 {
                // tree cluster
                placeInward("treeLarge", scale: 5, parent: parentNode, sample: s, sideOffset:  21)
                placeInward("treeLarge", scale: 5, parent: parentNode, sample: s, sideOffset: -21)
            } else {
                // grandstand
                placeInward("grandStandCovered", scale: 6, parent: parentNode, sample: s, sideOffset:  24)
                placeInward("grandStandCovered", scale: 6, parent: parentNode, sample: s, sideOffset: -24)
            }
        }
    }

    // MARK: - Placement helpers

    // Places a prop aligned with the track forward direction (barriers, lamp posts, gantries).
    private static func placeAlongTrack(_ name: String, scale: Float, parent: SCNNode,
                                         sample: PathSample, sideOffset: Float,
                                         facingForward: Bool = false) {
        guard let tmpl = loadTemplate(name, scale: scale) else { return }
        let node = tmpl.clone()
        node.simdPosition = sample.position + sample.right * sideOffset
        let angle = atan2(sample.forward.x, -sample.forward.z)
        node.simdEulerAngles = SIMD3<Float>(0, facingForward ? angle : angle + .pi / 2, 0)
        parent.addChildNode(node)
    }

    // Places a prop facing inward toward the track (grandstands, trees).
    private static func placeInward(_ name: String, scale: Float, parent: SCNNode,
                                     sample: PathSample, sideOffset: Float) {
        guard let tmpl = loadTemplate(name, scale: scale) else { return }
        let node = tmpl.clone()
        node.simdPosition = sample.position + sample.right * sideOffset
        let inward = sideOffset > 0 ? -sample.right : sample.right
        node.simdEulerAngles = SIMD3<Float>(0, atan2(inward.x, inward.z), 0)
        parent.addChildNode(node)
    }
}
