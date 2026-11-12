import SceneKit
import simd

/// Builds the track ribbon SCNNode by sweeping a cross-section profile
/// along all PathSamples.  Separate sub-nodes are added for kerbs and shoulders
/// so materials can be swapped independently.
final class TrackMeshBuilder {

    // Cross-section profile: (offsetRight m, heightUp m, slot)
    // Slots: 0 = road surface, 1 = kerb, 2 = shoulder, 3 = skirt down into the terrain.
    private static let profile: [(x: Float, y: Float, slot: Int)] = [
        (-11.2, -1.4, 3),   // skirt L
        (-10.0,  0.0, 2),   // shoulder L
        ( -7.5,  0.0, 2),
        ( -7.5,  0.0, 1),   // kerb L outer
        ( -5.5,  0.14, 1),  // kerb L inner (raised)
        ( -5.5,  0.0, 0),   // road L edge
        (  0.0,  0.0, 0),   // road centre
        (  5.5,  0.0, 0),   // road R edge
        (  5.5,  0.14, 1),  // kerb R inner
        (  7.5,  0.0, 1),   // kerb R outer
        (  7.5,  0.0, 2),   // shoulder R
        ( 10.0,  0.0, 3),
        ( 11.2, -1.4, 3),   // skirt R
    ]

    // Material indices returned by makeMaterials().
    private enum Mat: Int, CaseIterable {
        case tarmac, dirt, gravelRoad, kerb, gravelShoulder, pavement, concrete
    }

    private static func material(slot: Int, sample s: PathSample) -> Mat {
        switch slot {
        case 0:
            switch s.surface {
            case .tarmac: return .tarmac
            case .dirt: return .dirt
            case .gravel: return .gravelRoad
            }
        case 1: return .kerb
        default:
            if s.zone == .tunnel { return .concrete }
            if s.townInfluence > 0.5 { return .pavement }
            return .gravelShoulder
        }
    }

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

    private static func buildGeometry(path: TrackPath) -> (SCNGeometry, SCNGeometry) {
        let samples = path.samples
        let n = samples.count
        let p = profile.count

        var positions  = [SCNVector3]()
        var normals    = [SCNVector3]()
        var texcoords  = [CGPoint]()

        positions.reserveCapacity((n + 1) * p)
        normals.reserveCapacity((n + 1) * p)
        texcoords.reserveCapacity((n + 1) * p)

        let textureRepeats = max(1, (path.totalLength / 12).rounded())
        let tileSize = path.totalLength / textureRepeats
        for sampleIndex in 0...n {
            let s = samples[sampleIndex % n]
            let distance = sampleIndex == n ? path.totalLength : s.arcLength
            let v = CGFloat(distance / tileSize)
            for prof in profile {
                let offset = s.right * prof.x + s.up * prof.y
                let pos    = s.position + offset
                positions.append(SCNVector3(pos.x, pos.y, pos.z))
                normals.append(SCNVector3(s.up.x, s.up.y, s.up.z))
                let u = prof.slot == 0 ? prof.x / 11 + 0.5 : prof.x / 4
                texcoords.append(CGPoint(x: CGFloat(u), y: v))
            }
        }

        let slotCount = Mat.allCases.count
        var slotIndices: [[Int32]] = Array(repeating: [], count: slotCount)

        for si in 0..<n {
            let ni = si + 1
            for pi in 0..<(p - 1) {
                let a = Int32(si * p + pi)
                let b = Int32(si * p + pi + 1)
                let c = Int32(ni * p + pi)
                let d = Int32(ni * p + pi + 1)
                let slot = material(slot: profile[pi].slot, sample: samples[si]).rawValue
                slotIndices[slot].append(contentsOf: [a, b, c, b, d, c])
            }
        }

        let posSource = SCNGeometrySource(vertices: positions)
        let nrmSource = SCNGeometrySource(normals: normals)
        let uvSource  = SCNGeometrySource(textureCoordinates: texcoords)

        // One SCNGeometryElement per used material
        let materials = makeMaterials()
        var elements = [SCNGeometryElement]()
        var used = [SCNMaterial]()
        for (slot, idxs) in slotIndices.enumerated() where !idxs.isEmpty {
            elements.append(SCNGeometryElement(indices: idxs, primitiveType: .triangles))
            used.append(materials[slot])
        }

        let geo = SCNGeometry(sources: [posSource, nrmSource, uvSource], elements: elements)
        geo.materials = used

        // Physics uses the full mesh
        let allIndices = slotIndices.flatMap { $0 }
        let physElement = SCNGeometryElement(indices: allIndices, primitiveType: .triangles)
        let physGeo = SCNGeometry(sources: [posSource], elements: [physElement])

        return (geo, physGeo)
    }

    // MARK: - Materials (indexed by Mat)

    private static func makeMaterials() -> [SCNMaterial] {
        let asphalt = SCNMaterial()
        asphalt.name = "Arcade racing road"
        asphalt.lightingModel = .physicallyBased
        asphalt.diffuse.contents   = UIColor(white: 0.22, alpha: 1)
        asphalt.roughness.contents = 0.95
        asphalt.metalness.contents = 0
        asphalt.isDoubleSided      = true
        if let url = Bundle.main.url(forResource: "racing-road", withExtension: "png",
                                     subdirectory: "Textures") {
            asphalt.diffuse.contents = url
        } else {
            assertionFailure("Missing bundled racing road texture")
        }
        asphalt.diffuse.wrapS = .clamp
        asphalt.diffuse.wrapT = .repeat
        asphalt.diffuse.minificationFilter = .linear
        asphalt.diffuse.magnificationFilter = .linear
        asphalt.diffuse.mipFilter = .linear
        asphalt.diffuse.maxAnisotropy = 16

        func textured(_ image: UIImage, scale: SIMD2<Float>, clampU: Bool = false) -> SCNMaterial {
            let m = SCNMaterial()
            m.lightingModel = .physicallyBased
            m.diffuse.contents = image
            m.diffuse.wrapS = clampU ? .clamp : .repeat
            m.diffuse.wrapT = .repeat
            m.diffuse.mipFilter = .linear
            m.diffuse.maxAnisotropy = 16
            m.diffuse.contentsTransform = SCNMatrix4MakeScale(scale.x, scale.y, 1)
            m.roughness.contents = 0.95
            m.metalness.contents = 0
            m.isDoubleSided = true
            return m
        }

        let dirt = textured(ProceduralTextures.dirtRoad(seed: 21), scale: SIMD2(1, 1), clampU: true)
        let gravelRoad = textured(ProceduralTextures.gravel(seed: 22, tint: SIMD3(0.62, 0.58, 0.52)),
                                  scale: SIMD2(2.75, 3))
        let kerb = textured(ProceduralTextures.kerb(), scale: SIMD2(1, 1))
        kerb.roughness.contents = 0.7
        let shoulder = textured(ProceduralTextures.gravel(seed: 23), scale: SIMD2(1, 3))
        let pavement = textured(ProceduralTextures.pavement(seed: 24), scale: SIMD2(1, 3))
        let concrete = textured(ProceduralTextures.concrete(seed: 25), scale: SIMD2(1, 3))

        return [asphalt, dirt, gravelRoad, kerb, shoulder, pavement, concrete]
    }
}

// MARK: - Track decorations — procedurally generated props

final class TrackDecorations {

    // MARK: - Public entry point

    static func addDecorations(to parentNode: SCNNode, path: TrackPath, field: TerrainField) {
        let samples = path.samples
        let count   = samples.count

        let startSample = samples[0]
        parentNode.addChildNode(RaceProps.startGantry(sample: startSample))
        parentNode.addChildNode(RaceProps.flag(sample: startSample, side: -1))
        parentNode.addChildNode(RaceProps.flag(sample: startSample, side: 1))

        // Grandstands either side of the line, skipped where a footprint would hit a road.
        guard startSample.zone == nil, startSample.townInfluence < 0.2 else { return }
        var seed: UInt64 = 1
        for arc: Float in [-24, 22] {
            let index = Int((arc / path.totalLength * Float(count)).rounded())
            let s = path.sample(at: index)
            guard s.zone == nil, s.townInfluence < 0.2 else { continue }
            for side: Float in [-1, 1] {
                seed += 1
                if let stand = RaceProps.grandstand(sample: s, side: side, field: field, seed: seed) {
                    parentNode.addChildNode(stand)
                }
            }
        }
    }
}
