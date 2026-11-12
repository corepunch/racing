import SceneKit
import simd

/// Billboard tree sprites and forest walls baked by Tools/bake_tree_sprites.swift.
struct TreeSpriteManifest: Decodable {
    struct Sprite: Decodable {
        var name: String
        var biomes: [String]
        var uv: [Float]          // x, y, w, h normalised, origin top-left
        var height: Float
        var aspect: Float
        var category: String?
    }
    struct Wall: Decodable {
        var file: String
        var width: Float
        var height: Float
    }
    var atlas: String
    var sprites: [Sprite]
    var walls: [String: Wall]

    static let directory = "Textures/Trees"

    static func load(_ name: String) -> TreeSpriteManifest? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json", subdirectory: directory),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(TreeSpriteManifest.self, from: data)
    }

    static let shared = load("trees")

    static func image(_ file: String) -> UIImage? {
        let name = (file as NSString).deletingPathExtension
        guard let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: directory) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }
}

enum ForestBuilder {

    /// Cut-out foliage; billboards additionally turn about Y to face the active camera (or light, in shadow passes).
    private static func material(_ image: UIImage, billboard: Bool) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = billboard ? .constant : .lambert
        m.diffuse.contents = image
        m.diffuse.mipFilter = .linear
        // Mirror the painted wall on alternate repeats so its end silhouettes meet cleanly.
        m.diffuse.wrapS = billboard ? .clamp : .mirror
        m.diffuse.wrapT = .clamp
        m.isDoubleSided = true
        m.blendMode = .replace
        var modifiers: [SCNShaderModifierEntryPoint: String] = [
            .surface: "if (_surface.diffuse.a < 0.5) discard_fragment();",
        ]
        if billboard {
            modifiers[.geometry] = """
            float2 corner = _geometry.texcoords[1];
            float3 eye = scn_frame.inverseViewTransform[3].xyz;
            float2 d = normalize(eye.xz - _geometry.position.xz + float2(1e-4, 0.0));
            _geometry.position.xyz += float3(d.y, 0.0, -d.x) * corner.x + float3(0.0, corner.y, 0.0);
            _geometry.normal = float3(0.0, 1.0, 0.0);
            """
        }
        m.shaderModifiers = modifiers
        return m
    }

    /// Distance from the centreline to the forest wall for a given lap position.
    private static func wallDistance(_ noise: Noise2D, arc: Float) -> Float {
        66 + noise.fbm(arc / 140, 3.7, octaves: 2) * 30
    }

    static func build(field: TerrainField) -> SCNNode {
        let root = SCNNode()
        root.name = "forest"
        guard let manifest = TreeSpriteManifest.shared,
              let atlas = TreeSpriteManifest.image(manifest.atlas) else {
            assertionFailure("Missing baked tree sprites; run Tools/bake_tree_sprites.swift")
            return root
        }
        let env = field.env
        let biome = env.forest.rawValue
        let treeManifest: TreeSpriteManifest
        let treeAtlas: UIImage
        if let painted = TreeSpriteManifest.load("trees-painted"),
           painted.sprites.contains(where: { $0.biomes.contains(biome) }),
           let image = TreeSpriteManifest.image(painted.atlas) {
            (treeManifest, treeAtlas) = (painted, image)
        } else {
            (treeManifest, treeAtlas) = (manifest, atlas)
        }
        let sprites = treeManifest.sprites.filter { $0.biomes.contains(biome) && $0.category != "people" }
        guard !sprites.isEmpty else { return root }
        let noise = Noise2D(seed: env.seed &+ 405)

        if env.forest != .arid, let wall = manifest.walls[biome], let image = TreeSpriteManifest.image(wall.file) {
            root.addChildNode(forestWalls(field: field, wall: wall, material: material(image, billboard: false),
                                          noise: noise))
        }
        root.addChildNode(scatter(field: field, sprites: sprites, material: material(treeAtlas, billboard: true),
                                  noise: noise))
        let peopleManifest: TreeSpriteManifest
        let peopleAtlas: UIImage
        if let painted = TreeSpriteManifest.load("people-painted"),
           let image = TreeSpriteManifest.image(painted.atlas) {
            (peopleManifest, peopleAtlas) = (painted, image)
        } else {
            (peopleManifest, peopleAtlas) = (manifest, atlas)
        }
        let people = peopleManifest.sprites.filter { $0.category == "people" && $0.biomes.contains(biome) }
        if !people.isEmpty {
            root.addChildNode(spectators(field: field, sprites: people, material: material(peopleAtlas, billboard: true)))
        }
        return root
    }

    private static func forestChance(_ env: TrackDefinition.Environment, _ noise: Noise2D, _ x: Float, _ z: Float) -> Float {
        let forest = noise.fbm(x / 140, z / 140, octaves: 3) * 0.5 + 0.5
        return env.treeDensity * smoothstep(0.38, 0.7, forest)
    }

    /// Wall of trees along offset curves on both sides of the track, broken where there is
    /// no forest, water, a town or another stretch of road.
    private static func forestWalls(field: TerrainField, wall: TreeSpriteManifest.Wall, material: SCNMaterial,
                                    noise: Noise2D) -> SCNNode {
        let path = field.path
        let env = field.env
        let water = env.waterLevel ?? -.greatestFiniteMagnitude
        var mb = MeshBuilder(materialCount: 1)
        let up = SIMD3<Float>(0, 1, 0)

        for side: Float in [-1, 1] {
            var prev: (bottom: UInt32, top: UInt32, pos: SIMD3<Float>)?
            var u: Float = 0
            for i in stride(from: 0, through: path.stepCount, by: 4) {
                let s = path.sample(at: i)
                let rightH = simd_normalize(SIMD3(s.right.x, 0, s.right.z))
                let dist = wallDistance(noise, arc: s.arcLength)
                let p = s.position + rightH * side * dist
                let info = field.info(p.x, p.z)
                let near = path.samples[info.hit.index]
                let ok = info.hit.distance > dist - 10
                    && info.height > water + 1.2
                    && s.townInfluence < 0.2 && near.townInfluence < 0.2
                    && forestChance(env, noise, p.x, p.z) > 0.3
                guard ok else { prev = nil; continue }

                let base = SIMD3(p.x, info.height - 1.5, p.z)
                if let last = prev {
                    let step = simd_length(SIMD2(base.x - last.pos.x, base.z - last.pos.z))
                    if step > 30 { prev = nil }
                    u += step / wall.width
                }
                let b = mb.vertex(base, up, SIMD2(u, 1))
                let t = mb.vertex(base + up * wall.height, up, SIMD2(u, 0))
                if let last = prev { mb.quad(0, last.bottom, b, t, last.top) }
                prev = (b, t, base)
            }
        }
        let node = SCNNode(geometry: mb.geometry(materials: [material]))
        node.name = "forestWalls"
        PhysicsCategory.addStaticMesh(to: node, category: PhysicsCategory.obstacle)
        return node
    }

    /// Individual billboard trees between the road and the wall, densest just in front of it.
    private static func scatter(field: TerrainField, sprites: [TreeSpriteManifest.Sprite], material: SCNMaterial,
                                noise: Noise2D) -> SCNNode {
        let path = field.path
        let env = field.env
        var rng = SplitMix64(seed: env.seed &+ 404)
        let water = env.waterLevel ?? -.greatestFiniteMagnitude
        let chunkSize: Float = 160
        let spacing: Float = 6
        let lo = path.boundsMin - 320, hi = path.boundsMax + 320
        var chunks = [SIMD2<Int>: (mb: MeshBuilder, trunks: MeshBuilder, top: Float, trunkCount: Int)]()

        var z = lo.y
        while z < hi.y {
            var x = lo.x
            while x < hi.x {
                defer { x += spacing }
                let px = x + rng.float(-2.6...2.6), pz = z + rng.float(-2.6...2.6)
                var chance = forestChance(env, noise, px, pz)
                if chance <= 0 { continue }
                let info = field.info(px, pz)
                let s = path.samples[info.hit.index]
                let d = info.hit.distance
                let wallAt = wallDistance(noise, arc: s.arcLength)
                // Thicken toward the wall so it doesn't start abruptly; thin out behind it.
                chance *= d < wallAt ? 0.45 + 0.9 * smoothstep(wallAt - 40, wallAt - 4, d) : 0.35
                if rng.float() > chance { continue }
                if d < 16 || (s.townInfluence > 0.1 && d < 45) { continue }
                if s.tunnelInfluence > 0 && d < 22 { continue }
                if min(s.arcLength, path.totalLength - s.arcLength) < 50 && d < 40 { continue }
                if info.height < water + 1.6 { continue }

                let sprite = sprites[Int(rng.next() % UInt64(sprites.count))]
                let h = sprite.height * rng.float(0.8...1.25)
                let w = h * sprite.aspect
                let base = SIMD3(px, info.height - min(0.3, h * 0.04), pz)
                let (u0, v0) = (sprite.uv[0], sprite.uv[1])
                let (u1, v1) = (u0 + sprite.uv[2], v0 + sprite.uv[3])
                // Mirror half the trees for extra variety.
                let (ul, ur) = rng.float() < 0.5 ? (u0, u1) : (u1, u0)

                let key = SIMD2(Int((px / chunkSize).rounded(.down)), Int((pz / chunkSize).rounded(.down)))
                var chunk = chunks[key] ?? (MeshBuilder(materialCount: 1, secondUV: true), MeshBuilder(materialCount: 1), 0, 0)
                let n = SIMD3<Float>(0, 1, 0)
                let a = chunk.mb.vertex(base, n, SIMD2(ul, v1), uv2: SIMD2(-w / 2, 0))
                let b = chunk.mb.vertex(base, n, SIMD2(ur, v1), uv2: SIMD2(w / 2, 0))
                let c = chunk.mb.vertex(base, n, SIMD2(ur, v0), uv2: SIMD2(w / 2, h))
                let e = chunk.mb.vertex(base, n, SIMD2(ul, v0), uv2: SIMD2(-w / 2, h))
                chunk.mb.quad(0, a, b, c, e)
                // Billboards turn to face the camera; a small fixed trunk gives trees a
                // stable, solid footprint without treating their transparent canopy as a wall.
                if h >= 4 {
                    let trunkWidth = min(1.2, max(0.5, h * 0.065))
                    chunk.trunks.box(0, origin: base, basis: matrix_identity_float3x3,
                                     size: SIMD3(trunkWidth, max(2, h * 0.45), trunkWidth))
                    chunk.trunkCount += 1
                }
                chunk.top = max(chunk.top, h)
                chunks[key] = chunk
            }
            z += spacing
        }

        let root = SCNNode()
        root.name = "treeSprites"
        for (_, chunk) in chunks {
            let geo = chunk.mb.geometry(materials: [material])
            // Vertices sit at the trunk base; widen the bounds so culling sees the expanded quads.
            let (mn, mx) = geo.boundingBox
            let pad = chunk.top
            geo.boundingBox = (SCNVector3(mn.x - pad, mn.y, mn.z - pad), SCNVector3(mx.x + pad, mx.y + pad, mx.z + pad))
            root.addChildNode(SCNNode(geometry: geo))
            if chunk.trunkCount > 0 {
                let trunks = SCNNode(geometry: chunk.trunks.geometry(materials: [SCNMaterial()]))
                // Hidden SceneKit nodes do not participate in physics queries.
                trunks.opacity = 0
                trunks.castsShadow = false
                PhysicsCategory.addStaticMesh(to: trunks, category: PhysicsCategory.obstacle)
                root.addChildNode(trunks)
            }
        }
        return root
    }

    private static func spectators(field: TerrainField, sprites: [TreeSpriteManifest.Sprite],
                                   material: SCNMaterial) -> SCNNode {
        var rng = SplitMix64(seed: field.env.seed &+ 910)
        var mesh = MeshBuilder(materialCount: 1, secondUV: true)
        let path = field.path
        let water = field.env.waterLevel ?? -.greatestFiniteMagnitude
        let up = SIMD3<Float>(0, 1, 0)
        for index in stride(from: 0, to: path.stepCount, by: 8) {
            let sample = path.sample(at: index)
            if sample.tunnelInfluence > 0.05 { continue }
            let atStart = min(sample.arcLength, path.totalLength - sample.arcLength) < 65
            let inTown = sample.townInfluence > 0.8
            if !atStart && !inTown && rng.float() > 0.07 { continue }
            let right = simd_normalize(SIMD3(sample.right.x, 0, sample.right.z))
            let forward = simd_normalize(SIMD3(sample.forward.x, 0, sample.forward.z))
            for side: Float in [-1, 1] {
                if !atStart && rng.float() > 0.65 { continue }
                let count = atStart ? 5 : Int(rng.next() % 3) + 2
                for person in 0..<count {
                    let offset = Float(person) * 1.0 - Float(count - 1) * 0.5
                    let distance = inTown ? rng.float(10.3...11.8) : rng.float(11.5...13.0)
                    let position = sample.position + right * side * distance
                        + forward * (offset + rng.float(-0.15...0.15))
                    let info = field.info(position.x, position.z)
                    if info.hit.distance < sample.halfWidth + 4.2 || info.height < water + 0.6 { continue }
                    if abs(info.height - field.height(position.x + 0.6, position.z + 0.6)) > 0.4 { continue }
                    if path.samples[info.hit.index].tunnelInfluence > 0.05 { continue }
                    let sprite = sprites[Int(rng.next() % UInt64(sprites.count))]
                    let height = sprite.height * rng.float(0.94...1.06)
                    let width = height * sprite.aspect
                    let base = SIMD3(position.x, info.height, position.z)
                    let left = sprite.uv[0], top = sprite.uv[1]
                    let rightUV = left + sprite.uv[2], bottom = top + sprite.uv[3]
                    let first = mesh.vertex(base, up, SIMD2(left, bottom), uv2: SIMD2(-width / 2, 0))
                    let second = mesh.vertex(base, up, SIMD2(rightUV, bottom), uv2: SIMD2(width / 2, 0))
                    let third = mesh.vertex(base, up, SIMD2(rightUV, top), uv2: SIMD2(width / 2, height))
                    let fourth = mesh.vertex(base, up, SIMD2(left, top), uv2: SIMD2(-width / 2, height))
                    mesh.quad(0, first, second, third, fourth)
                }
            }
        }
        let geometry = mesh.geometry(materials: [material])
        let (minimum, maximum) = geometry.boundingBox
        geometry.boundingBox = (SCNVector3(minimum.x - 2, minimum.y, minimum.z - 2),
                                SCNVector3(maximum.x + 2, maximum.y + 2.2, maximum.z + 2))
        let node = SCNNode(geometry: geometry)
        node.name = "spectatorSprites"
        return node
    }
}
