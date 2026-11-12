import SceneKit
import simd

/// Fast nearest-centreline queries via a uniform bucket grid of samples.
struct TrackLocator {
    struct Hit {
        var index: Int
        var lateral: Float      // signed offset along the sample's right vector
        var distance: Float     // horizontal distance to the centreline
    }

    private let samples: [PathSample]
    private let cell: Float = 24
    private let origin: SIMD2<Float>
    private let cols: Int, rows: Int
    private var buckets: [[Int32]]

    init(path: TrackPath) {
        samples = path.samples
        origin = path.boundsMin - 40
        let extent = path.boundsMax + 40 - origin
        cols = Int(extent.x / cell) + 1
        rows = Int(extent.y / cell) + 1
        buckets = Array(repeating: [], count: cols * rows)
        for (i, s) in samples.enumerated() {
            let c = bucket(SIMD2(s.position.x, s.position.z))
            buckets[c.y * cols + c.x].append(Int32(i))
        }
    }

    private func bucket(_ p: SIMD2<Float>) -> SIMD2<Int> {
        let q = (p - origin) / cell
        return SIMD2(min(max(Int(q.x), 0), cols - 1), min(max(Int(q.y), 0), rows - 1))
    }

    func nearest(_ x: Float, _ z: Float) -> Hit {
        let p = SIMD2(x, z)
        let c = bucket(p)
        var best = -1
        var bestD = Float.greatestFiniteMagnitude
        var ring = 0
        while ring < max(cols, rows) {
            for gy in (c.y - ring)...(c.y + ring) where gy >= 0 && gy < rows {
                for gx in (c.x - ring)...(c.x + ring) where gx >= 0 && gx < cols {
                    if max(abs(gx - c.x), abs(gy - c.y)) != ring { continue }
                    for i in buckets[gy * cols + gx] {
                        let s = samples[Int(i)].position
                        let d = simd_length_squared(SIMD2(s.x, s.z) - p)
                        if d < bestD { bestD = d; best = Int(i) }
                    }
                }
            }
            // Points outside the grid can be far from every bucket; distance to the
            // ring edge bounds what any further ring could contain.
            let outside = max(0, max(origin.x - x, x - (origin.x + Float(cols) * cell),
                                     origin.y - z, z - (origin.y + Float(rows) * cell)))
            if best >= 0 && sqrt(bestD) < Float(ring) * cell + outside { break }
            ring += 1
        }
        let s = samples[best]
        let d = SIMD3(x - s.position.x, 0, z - s.position.z)
        let rh = simd_normalize(SIMD3(s.right.x, 0, s.right.z))
        let lateral = simd_dot(d, rh)
        return Hit(index: best, lateral: lateral, distance: abs(lateral))
    }
}

/// Height field shared by the terrain mesh and every placed object so props sit on the ground.
final class TerrainField {
    let path: TrackPath
    let locator: TrackLocator
    let env: TrackDefinition.Environment
    private let noise: Noise2D
    private let detail: Noise2D

    /// Terrain just under the road edge skirt.
    static let corridor: Float = 11.5
    /// Tunnels keep the ground below the road out to here (hidden by the tube and roof).
    static let tunnelCorridor: Float = 14

    init(path: TrackPath) {
        self.path = path
        self.env = path.definition.environment
        locator = TrackLocator(path: path)
        noise = Noise2D(seed: env.seed)
        detail = Noise2D(seed: env.seed &+ 99)
    }

    /// Signed water distance: > 0 means inside a lake or the sea.
    func waterDistance(_ x: Float, _ z: Float) -> Float {
        var best = -Float.greatestFiniteMagnitude
        let wobble = detail.fbm(x / 90, z / 90, octaves: 3) * 45
        for body in env.water {
            switch body {
            case let .coast(dir, offset):
                best = max(best, simd_dot(SIMD2(x, z), dir) - offset + wobble)
            case let .lake(center, radius):
                best = max(best, radius - simd_length(SIMD2(x, z) - center) + wobble * 0.6)
            }
        }
        return best
    }

    /// Terrain without the road's influence.
    func naturalHeight(_ x: Float, _ z: Float, trackDistance: Float) -> Float {
        let s = env.hillScale
        var h = env.baseHeight + env.hillAmplitude * noise.fbm(x / s, z / s, octaves: 5)
        let ridge = noise.ridged(x / (s * 2.2) + 31.7, z / (s * 2.2) - 12.3, octaves: 5)
        h += env.mountainAmplitude * smoothstep(90, 420, trackDistance) * ridge * ridge
        h += detail.fbm(x / 18, z / 18, octaves: 3) * 1.2

        if let water = env.waterLevel, !env.water.isEmpty {
            let c = waterDistance(x, z)
            if c > -160 {
                // Gentle beach ramp that continues below the waterline.
                let beach = water + 0.8 - c * 0.06
                let seabed = water - 6
                h = c < 0 ? mix(h, beach, smoothstep(-160, 0, c)) : max(beach, seabed)
            }
        }
        return h
    }

    struct Info {
        var height: Float
        var hit: TrackLocator.Hit
        var natural: Float
    }

    func info(_ x: Float, _ z: Float) -> Info {
        let hit = locator.nearest(x, z)
        let s = path.samples[hit.index]
        let d = hit.distance
        var natural = naturalHeight(x, z, trackDistance: d)
        let road = s.position.y + hit.lateral * s.right.y

        // Towns flatten the surroundings so buildings sit level with the street.
        if s.townInfluence > 0 {
            natural = mix(natural, road - 0.2, s.townInfluence * (1 - smoothstep(30, 90, d)))
        }
        // Mountains over tunnels and cuttings leading into them, fading with distance so
        // the nearest-sample regions don't leave wedges across the landscape.
        if s.tunnelInfluence > 0 {
            let reach = 1 - smoothstep(45, 120, d)
            let infl = s.tunnelInfluence
            let mountain = s.position.y + infl * 10 + s.tunnelHill
                * (0.6 * infl * smoothstep(20, 90, d) + s.tunnelDepth * exp(-pow(max(d - 15, 0) / 90, 2)))
            let raised = mix(natural, max(natural, mountain), infl)
            natural = mix(natural, raised, reach)
        }

        let h: Float
        if s.zone == .tunnel {
            h = d < Self.tunnelCorridor ? road - 2 : natural
        } else {
            let blend = mix(42, 12, max(s.tunnelInfluence, s.townInfluence * 0.5))
            let t = smoothstep(Self.corridor, Self.corridor + blend, d)
            h = mix(road - 0.6, natural, t)
        }
        return Info(height: h, hit: hit, natural: natural)
    }

    func height(_ x: Float, _ z: Float) -> Float { info(x, z).height }
}

// MARK: - Terrain mesh + splat map

enum TerrainBuilder {

    struct Result {
        var node: SCNNode
        var material: SCNMaterial
    }

    static func build(field: TerrainField, cellSize: Float = 3.5, margin: Float = 480) -> Result {
        let path = field.path
        let minXZ = path.boundsMin - margin
        let maxXZ = path.boundsMax + margin
        let cols = Int((maxXZ.x - minXZ.x) / cellSize) + 1
        let rows = Int((maxXZ.y - minXZ.y) / cellSize) + 1
        let env = field.env

        // Height + splat weights per vertex (parallel by row).
        var heights = [Float](repeating: 0, count: cols * rows)
        var hits = [TrackLocator.Hit](repeating: .init(index: 0, lateral: 0, distance: 0), count: cols * rows)
        heights.withUnsafeMutableBufferPointer { hb in
            hits.withUnsafeMutableBufferPointer { ib in
                let hp = hb.baseAddress!, ip = ib.baseAddress!
                DispatchQueue.concurrentPerform(iterations: rows) { r in
                    for c in 0..<cols {
                        let x = minXZ.x + Float(c) * cellSize, z = minXZ.y + Float(r) * cellSize
                        let info = field.info(x, z)
                        hp[r * cols + c] = info.height
                        ip[r * cols + c] = info.hit
                    }
                }
            }
        }

        func h(_ c: Int, _ r: Int) -> Float {
            heights[min(max(r, 0), rows - 1) * cols + min(max(c, 0), cols - 1)]
        }

        let detail = Noise2D(seed: env.seed &+ 7)
        var normals = [SIMD3<Float>](repeating: .zero, count: cols * rows)
        var splat = [UInt8](repeating: 0, count: cols * rows * 4)
        for r in 0..<rows {
            for c in 0..<cols {
                let i = r * cols + c
                let n = simd_normalize(SIMD3(h(c - 1, r) - h(c + 1, r), 2 * cellSize, h(c, r - 1) - h(c, r + 1)))
                normals[i] = n
                let x = minXZ.x + Float(c) * cellSize, z = minXZ.y + Float(r) * cellSize
                let y = heights[i]
                let hit = hits[i]
                let s = path.samples[hit.index]
                let wobble = detail.fbm(x / 25, z / 25, octaves: 3)

                let slope = 1 - n.y
                var rock = smoothstep(env.rockSlope * 0.35, env.rockSlope * 0.6, slope + wobble * 0.08)
                rock = max(rock, smoothstep(0.35, 0.8, wobble) * smoothstep(60, 140, hit.distance) * 0.7)
                var sand: Float = 0
                if let water = env.waterLevel, !env.water.isEmpty {
                    sand = 1 - smoothstep(water + 1.2, water + 2.6, y + wobble * 1.5)
                }
                sand = max(sand, smoothstep(0.45, 0.75, -wobble) * 0.5 * (env.forest == .arid ? 1 : 0))
                var pave = s.townInfluence * (1 - smoothstep(18, 26, hit.distance + wobble * 3))
                if s.zone == .tunnel || s.tunnelInfluence > 0.6 { pave = 0 }
                // Roadside verge: worn earth/gravel strip right next to the skirt.
                let verge = (1 - smoothstep(12, 16, hit.distance + wobble * 2)) * (1 - pave)
                sand = max(sand, verge * 0.55)
                if s.zone == .tunnel && hit.distance < TerrainField.tunnelCorridor + 6 { rock = 0; sand = 0 }

                splat[i * 4] = UInt8(min(rock, 1) * 255)
                splat[i * 4 + 1] = UInt8(min(sand, 1) * 255)
                splat[i * 4 + 2] = UInt8(min(pave, 1) * 255)
                splat[i * 4 + 3] = 255
            }
        }

        let material = terrainMaterial(env: env, splat: splat, cols: cols, rows: rows,
                                       origin: minXZ, cellSize: cellSize)

        // Chunked mesh so SceneKit can frustum-cull and shadow cascades stay cheap.
        let root = SCNNode()
        root.name = "terrain"
        let chunk = 48
        for r0 in stride(from: 0, to: rows - 1, by: chunk) {
            for c0 in stride(from: 0, to: cols - 1, by: chunk) {
                let r1 = min(r0 + chunk, rows - 1), c1 = min(c0 + chunk, cols - 1)
                var mb = MeshBuilder(materialCount: 1)
                let w = c1 - c0 + 1
                for r in r0...r1 {
                    for c in c0...c1 {
                        let i = r * cols + c
                        let x = minXZ.x + Float(c) * cellSize, z = minXZ.y + Float(r) * cellSize
                        mb.vertex(SIMD3(x, heights[i], z), normals[i], SIMD2(x, z))
                    }
                }
                for r in 0..<(r1 - r0) {
                    for c in 0..<(c1 - c0) {
                        let a = UInt32(r * w + c), b = a + 1, d = UInt32((r + 1) * w + c), e = d + 1
                        mb.triangle(0, a, d, b)
                        mb.triangle(0, b, d, e)
                    }
                }
                let node = SCNNode(geometry: mb.geometry(materials: [material]))
                PhysicsCategory.addStaticMesh(to: node, category: PhysicsCategory.terrain)
                root.addChildNode(node)
            }
        }
        return Result(node: root, material: material)
    }

    /// Splat-mapped terrain: grass base with rock / sand / pavement layers from an RGB weight map.
    static func terrainMaterial(env: TrackDefinition.Environment, splat: [UInt8], cols: Int, rows: Int,
                                origin: SIMD2<Float>, cellSize: Float) -> SCNMaterial {
        let p = env.palette
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.roughness.contents = 0.95
        m.metalness.contents = 0
        // A texture (not a colour) so SceneKit provides _surface.diffuseTexcoord.
        m.diffuse.contents = ProceduralTextures.image(width: 4, height: 4) { _, _ in SIMD3(repeating: 1) }
        m.diffuse.wrapS = .repeat
        m.diffuse.wrapT = .repeat

        func prop(_ image: Any) -> SCNMaterialProperty {
            let prop = SCNMaterialProperty(contents: image)
            prop.wrapS = .repeat
            prop.wrapT = .repeat
            prop.mipFilter = .linear
            prop.minificationFilter = .linear
            prop.magnificationFilter = .linear
            prop.maxAnisotropy = 8
            return prop
        }

        let splatData = Data(splat) as CFData
        let splatImage = CGImage(width: cols, height: rows, bitsPerComponent: 8, bitsPerPixel: 32,
                                 bytesPerRow: cols * 4, space: CGColorSpaceCreateDeviceRGB(),
                                 bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                                 provider: CGDataProvider(data: splatData)!, decode: nil,
                                 shouldInterpolate: true, intent: .defaultIntent)!
        let splatProp = prop(splatImage)
        splatProp.wrapS = .clamp
        splatProp.wrapT = .clamp
        splatProp.mipFilter = .none

        m.setValue(prop(ProceduralTextures.grass(p, seed: env.seed &+ 1)), forKey: "grassTex")
        m.setValue(prop(ProceduralTextures.rock(p, seed: env.seed &+ 2)), forKey: "rockTex")
        m.setValue(prop(ProceduralTextures.sand(p, seed: env.seed &+ 3)), forKey: "sandTex")
        m.setValue(prop(ProceduralTextures.pavement(seed: env.seed &+ 4)), forKey: "paveTex")
        m.setValue(splatProp, forKey: "splatTex")
        // Vertex texcoords are world XZ metres; map them onto splat texel centres.
        let scale = 1 / (Float(cols) * cellSize)
        m.setValue(NSValue(scnVector4: SCNVector4(origin.x - cellSize / 2, origin.y - cellSize / 2,
                                                  scale, Float(rows) * cellSize * scale)),
                   forKey: "splatRect")

        m.shaderModifiers = [.surface: """
        #pragma arguments
        texture2d<float> grassTex;
        texture2d<float> rockTex;
        texture2d<float> sandTex;
        texture2d<float> paveTex;
        texture2d<float> splatTex;
        float4 splatRect;
        #pragma body
        constexpr sampler tile(filter::linear, mip_filter::linear, address::repeat, max_anisotropy(8));
        constexpr sampler clampS(filter::linear, address::clamp_to_edge);
        float2 world = _surface.diffuseTexcoord;
        float2 suv = (world - splatRect.xy) * splatRect.z;
        suv.y /= splatRect.w;
        float3 w = splatTex.sample(clampS, suv).rgb;

        float3 g1 = grassTex.sample(tile, world / 7.0).rgb;
        float3 g2 = grassTex.sample(tile, world / 41.0 + 0.37).rgb;
        float3 grass = mix(g1, g2, 0.4);
        float3 rockC = rockTex.sample(tile, world / 11.0).rgb * (rockTex.sample(tile, world / 57.0).rgb * 0.8 + 0.45);
        float3 sandC = sandTex.sample(tile, world / 6.0).rgb;
        float3 paveC = paveTex.sample(tile, world / 6.0).rgb;

        // Height-aware blends: texture detail breaks up the splat boundaries.
        float rh = dot(rockC, float3(0.33));
        float rw = smoothstep(0.0, 1.0, saturate(w.r * 1.6 - 0.3 + (rh - 0.45)));
        float sw = smoothstep(0.0, 1.0, saturate(w.g * 1.4 - 0.2 + (dot(g1, float3(0.33)) - 0.3) * -0.8));
        float3 c = mix(grass, sandC, sw);
        c = mix(c, rockC, rw);
        c = mix(c, paveC, saturate(w.b * 1.5 - 0.25));
        _surface.diffuse = float4(c, 1.0);
        """]
        return m
    }

    // MARK: - Water

    static func water(field: TerrainField, level: Float) -> SCNNode {
        let path = field.path
        let size = path.boundsMax - path.boundsMin + 1400
        let center = (path.boundsMax + path.boundsMin) / 2
        let plane = SCNPlane(width: CGFloat(size.x), height: CGFloat(size.y))
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = UIColor(red: 0.06, green: 0.22, blue: 0.28, alpha: 1)
        m.metalness.contents = 0.0
        m.roughness.contents = 0.08
        m.normal.contents = ProceduralTextures.waterNormal(seed: field.env.seed &+ 11)
        m.normal.intensity = 0.55
        m.normal.wrapS = .repeat
        m.normal.wrapT = .repeat
        m.normal.mipFilter = .linear
        m.normal.contentsTransform = SCNMatrix4MakeScale(Float(size.x) / 24, Float(size.y) / 24, 1)
        m.shaderModifiers = [
            .geometry: """
            _geometry.texcoords[0] += float2(scn_frame.time * 0.0018, scn_frame.time * 0.0011);
            """,
            .fragment: """
            float3 V = normalize(-_surface.position);
            float fres = pow(1.0 - saturate(dot(_surface.normal, V)), 4.0);
            _output.color.rgb = mix(_output.color.rgb, float3(0.62, 0.72, 0.76), fres * 0.65);
            """,
        ]
        plane.firstMaterial = m
        let node = SCNNode(geometry: plane)
        node.name = "water"
        node.eulerAngles.x = -.pi / 2
        node.simdPosition = SIMD3(center.x, level, center.y)
        node.castsShadow = false
        return node
    }
}
