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

// MARK: - Track decorations (buildings, lamp posts)

final class TrackDecorations {

    static func addDecorations(to parentNode: SCNNode, path: TrackPath) {
        let samples = path.samples
        let count   = samples.count
        // Place a building cluster every ~15 samples on the outer edge
        let step = 15
        var idx = 0
        while idx < count {
            let s = samples[idx]
            addBuildingCluster(parent: parentNode, sample: s, side: (idx / step) % 2 == 0 ? 1 : -1)
            idx += step
        }

        // Lamp posts every ~10 samples on both sides
        for i in stride(from: 0, to: count, by: 10) {
            addLampPost(parent: parentNode, sample: samples[i], side:  1)
            addLampPost(parent: parentNode, sample: samples[i], side: -1)
        }
    }

    // MARK: Buildings

    private static func addBuildingCluster(parent: SCNNode, sample: PathSample, side: Float) {
        let count = Int.random(in: 2...5)
        for k in 0..<count {
            let w      = Float.random(in: 6...14)
            let d      = Float.random(in: 6...14)
            let h      = Float.random(in: 8...28)
            let offsetR = side * (22 + Float(k) * (w + 2) + Float.random(in: 0...3))
            let offsetF = Float.random(in: -4...4)
            let centre = sample.position + sample.right * offsetR + sample.forward * offsetF
                       + SIMD3<Float>(0, h * 0.5, 0)

            let box      = SCNBox(width: CGFloat(w), height: CGFloat(h), length: CGFloat(d), chamferRadius: 0.3)
            box.firstMaterial           = buildingMaterial()
            let node                    = SCNNode(geometry: box)
            node.position               = SCNVector3(centre.x, centre.y, centre.z)
            node.eulerAngles.y          = Float.random(in: -0.3...0.3)
            parent.addChildNode(node)
        }
    }

    private static func buildingMaterial() -> SCNMaterial {
        let mat = SCNMaterial()
        // Random muted building colour
        let grey = CGFloat.random(in: 0.35...0.65)
        mat.diffuse.contents = UIColor(
            red: grey + CGFloat.random(in: -0.05...0.05),
            green: grey + CGFloat.random(in: -0.05...0.05),
            blue: grey + CGFloat.random(in: -0.05...0.05),
            alpha: 1
        )
        mat.roughness.contents = 0.85
        return mat
    }

    // MARK: Lamp posts

    private static func addLampPost(parent: SCNNode, sample: PathSample, side: Float) {
        let poleR: CGFloat = 0.08, poleH: CGFloat = 6
        let armL: CGFloat = 1.2

        let pole       = SCNCylinder(radius: poleR, height: poleH)
        pole.firstMaterial           = poleMaterial()
        let poleNode                 = SCNNode(geometry: pole)

        let offsetR    = side * (sample.halfWidth + 1.2)
        let base       = sample.position + sample.right * offsetR + SIMD3<Float>(0, Float(poleH * 0.5), 0)
        poleNode.position            = SCNVector3(base.x, base.y, base.z)

        // Horizontal arm
        let arm        = SCNCylinder(radius: 0.04, height: armL)
        arm.firstMaterial            = poleMaterial()
        let armNode                  = SCNNode(geometry: arm)
        armNode.eulerAngles.z        = .pi * 0.5
        armNode.position             = SCNVector3(0, Float(poleH * 0.5) - 0.1, 0)
        poleNode.addChildNode(armNode)

        // Lamp head
        let lamp       = SCNSphere(radius: 0.25)
        lamp.firstMaterial           = lampMaterial()
        let lampNode                 = SCNNode(geometry: lamp)
        lampNode.position            = SCNVector3(Float(armL * 0.5) * side, 0, 0)
        armNode.addChildNode(lampNode)

        parent.addChildNode(poleNode)
    }

    private static func poleMaterial() -> SCNMaterial {
        let m = SCNMaterial()
        m.diffuse.contents = UIColor(white: 0.55, alpha: 1)
        m.metalness.contents = 0.6
        m.roughness.contents = 0.4
        return m
    }

    private static func lampMaterial() -> SCNMaterial {
        let m = SCNMaterial()
        m.diffuse.contents    = UIColor(red: 1, green: 0.95, blue: 0.7, alpha: 1)
        m.emission.contents   = UIColor(red: 1, green: 0.95, blue: 0.7, alpha: 1)
        m.roughness.contents  = 0.1
        return m
    }
}
