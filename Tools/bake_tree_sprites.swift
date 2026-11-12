// Bakes Kenney Nature Kit (CC0) trees into billboard sprites and tileable forest walls.
// Usage (repo root):
//   swiftc -O Tools/bake_tree_sprites.swift -o /tmp/bake_trees && /tmp/bake_trees
import AppKit
import SceneKit
import ImageIO
import UniformTypeIdentifiers

struct Spec {
    var file: String
    var height: Float           // metres in game
    var biomes: [String]
}

let specs: [Spec] = [
    Spec(file: "tree_pineTallA_detailed", height: 18, biomes: ["alpine"]),
    Spec(file: "tree_pineTallB_detailed", height: 17, biomes: ["alpine"]),
    Spec(file: "tree_pineTallC_detailed", height: 19, biomes: ["alpine", "temperate"]),
    Spec(file: "tree_pineTallD_detailed", height: 16, biomes: ["alpine"]),
    Spec(file: "tree_pineRoundA", height: 12, biomes: ["alpine", "temperate"]),
    Spec(file: "tree_pineRoundC", height: 13, biomes: ["alpine"]),
    Spec(file: "tree_pineRoundE", height: 11, biomes: ["alpine", "temperate"]),
    Spec(file: "tree_pineDefaultA", height: 14, biomes: ["alpine"]),
    Spec(file: "tree_pineDefaultB", height: 13, biomes: ["alpine", "coastal"]),
    Spec(file: "tree_cone", height: 12, biomes: ["alpine", "temperate"]),
    Spec(file: "tree_cone_dark", height: 13, biomes: ["alpine"]),
    Spec(file: "tree_oak", height: 12, biomes: ["temperate"]),
    Spec(file: "tree_oak_dark", height: 12, biomes: ["temperate", "alpine"]),
    Spec(file: "tree_detailed", height: 11, biomes: ["temperate", "coastal"]),
    Spec(file: "tree_detailed_dark", height: 11, biomes: ["temperate", "alpine"]),
    Spec(file: "tree_default", height: 10, biomes: ["temperate", "coastal"]),
    Spec(file: "tree_fat", height: 9, biomes: ["temperate"]),
    Spec(file: "tree_tall", height: 14, biomes: ["temperate"]),
    Spec(file: "tree_thin", height: 12, biomes: ["temperate"]),
    Spec(file: "tree_simple", height: 9, biomes: ["temperate", "coastal"]),
    Spec(file: "tree_small", height: 6, biomes: ["temperate", "arid"]),
    Spec(file: "tree_oak_fall", height: 12, biomes: ["temperate"]),
    Spec(file: "tree_detailed_fall", height: 11, biomes: ["temperate"]),
    Spec(file: "tree_thin_fall", height: 11, biomes: ["arid"]),
    Spec(file: "tree_palmTall", height: 13, biomes: ["coastal"]),
    Spec(file: "tree_palmDetailedTall", height: 14, biomes: ["coastal"]),
    Spec(file: "tree_palmBend", height: 11, biomes: ["coastal"]),
    Spec(file: "tree_palmDetailedShort", height: 8, biomes: ["coastal"]),
    Spec(file: "tree_plateau", height: 9, biomes: ["arid"]),
    Spec(file: "tree_plateau_dark", height: 9, biomes: ["arid"]),
    Spec(file: "plant_bushLarge", height: 2.6, biomes: ["temperate", "coastal", "arid", "alpine"]),
    Spec(file: "plant_bushDetailed", height: 2.2, biomes: ["temperate", "coastal", "arid"]),
]
let biomes = ["alpine", "temperate", "coastal", "arid"]

let repo = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let kit = repo.appendingPathComponent("Resources/Kenney/nature-kit")
let outDir = repo.appendingPathComponent("Resources/Textures/Trees")
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

// MARK: - Model loading

/// Foliage hue/saturation/brightness-scale per biome; Kenney's stock teal reads as fake next to terrain.
let foliage: [String: (h: CGFloat, s: CGFloat, b: CGFloat)] = [
    "alpine": (0.30, 0.55, 0.62), "temperate": (0.26, 0.62, 0.72),
    "coastal": (0.23, 0.60, 0.78), "arid": (0.19, 0.45, 0.70),
]

func recolor(_ node: SCNNode, biome: String, autumn: Bool) {
    let tint = foliage[biome]!
    node.enumerateHierarchy { n, _ in
        guard let geo = n.geometry else { return }
        let copy = geo.copy() as! SCNGeometry
        copy.materials = geo.materials.map { original in
            let m = original.copy() as! SCNMaterial
            guard let c = (m.diffuse.contents as? NSColor)?.usingColorSpace(.sRGB) else { return m }
            var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            c.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
            if h > 0.3 && h < 0.62 {
                h = tint.h + (h - 0.47) * 0.3
                s = tint.s * min(s / 0.7, 1.3)
                b *= tint.b
            } else if (h < 0.1 || h > 0.9) && s < 0.5 && !autumn {
                h = 0.07; s = 0.5; b *= 0.62
            }
            m.diffuse.contents = NSColor(hue: h, saturation: s, brightness: b, alpha: a)
            return m
        }
        n.geometry = copy
    }
}

var models: [String: (node: SCNNode, size: SIMD3<Float>)] = [:]
func model(_ name: String, biome: String) -> (node: SCNNode, size: SIMD3<Float>) {
    let key = "\(name)/\(biome)"
    if let m = models[key] { return m }
    let url = kit.appendingPathComponent("\(name).usdz")
    guard let scene = try? SCNScene(url: url, options: [.convertToYUp: true]) else { fatalError("Missing \(url.path)") }
    recolor(scene.rootNode, biome: biome, autumn: name.hasSuffix("_fall"))
    let content = SCNNode()
    content.addChildNode(scene.rootNode)
    let (mn, mx) = content.boundingBox
    content.simdPosition = -SIMD3(Float(mn.x + mx.x) / 2, Float(mn.y), Float(mn.z + mx.z) / 2)
    let root = SCNNode()
    root.addChildNode(content)
    let size = SIMD3(Float(mx.x - mn.x), Float(mx.y - mn.y), Float(mx.z - mn.z))
    models[key] = (root, size)
    return (root, size)
}

// MARK: - Rendering

let device = MTLCreateSystemDefaultDevice()!

func stage(fog: Bool) -> SCNScene {
    let scene = SCNScene()
    scene.background.contents = NSColor.clear
    let sun = SCNLight()
    sun.type = .directional
    sun.intensity = 1150
    sun.color = NSColor(red: 1, green: 0.97, blue: 0.9, alpha: 1)
    let sunNode = SCNNode()
    sunNode.light = sun
    sunNode.eulerAngles = SCNVector3(-0.75, 0.55, 0)
    scene.rootNode.addChildNode(sunNode)
    let amb = SCNLight()
    amb.type = .ambient
    amb.intensity = 520
    amb.color = NSColor(red: 0.75, green: 0.82, blue: 0.9, alpha: 1)
    let ambNode = SCNNode()
    ambNode.light = amb
    scene.rootNode.addChildNode(ambNode)
    if fog {
        // Rows further back read darker, like the inside of a dense forest.
        scene.fogColor = NSColor(red: 0.07, green: 0.10, blue: 0.07, alpha: 1)
        scene.fogStartDistance = 42
        scene.fogEndDistance = 95
        scene.fogDensityExponent = 1.2
    }
    return scene
}

func orthoCamera(center: SIMD3<Float>, halfHeight: Float, distance: Float = 60) -> SCNNode {
    let cam = SCNCamera()
    cam.usesOrthographicProjection = true
    cam.orthographicScale = Double(halfHeight)
    cam.zNear = 0.1
    cam.zFar = Double(distance + 200)
    let node = SCNNode()
    node.camera = cam
    node.simdPosition = center + SIMD3(0, 0, distance)
    return node
}

/// Straight-alpha RGBA pixels from a render.
func render(_ scene: SCNScene, camera: SCNNode, width: Int, height: Int) -> [UInt8] {
    scene.rootNode.addChildNode(camera)
    let r = SCNRenderer(device: device, options: nil)
    r.scene = scene
    r.pointOfView = camera
    let image = r.snapshot(atTime: 0, with: CGSize(width: width, height: height), antialiasingMode: .multisampling4X)
    camera.removeFromParentNode()
    let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
    var px = [UInt8](repeating: 0, count: width * height * 4)
    let ctx = CGContext(data: &px, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
    // Binary cut-out: low-alpha edge texels have unreliable (bright) unpremultiplied colour.
    for i in stride(from: 0, to: px.count, by: 4) {
        let a = px[i + 3]
        if a < 128 {
            px[i] = 0; px[i + 1] = 0; px[i + 2] = 0; px[i + 3] = 0
        } else if a < 255 {
            let f = Float(a) / 255
            for c in 0..<3 { px[i + c] = UInt8(min(255, Float(px[i + c]) / f)) }
            px[i + 3] = 255
        }
    }
    return px
}

/// Push colour into transparent texels so filtering/mipmaps don't produce dark fringes.
func dilate(_ px: inout [UInt8], width: Int, height: Int, passes: Int) {
    var filled = (0..<(width * height)).map { px[$0 * 4 + 3] > 0 }
    for _ in 0..<passes {
        var next = filled
        var out = px
        for y in 0..<height {
            for x in 0..<width where !filled[y * width + x] {
                var sum = SIMD3<Int>(0, 0, 0), n = 0
                for (dx, dy) in [(-1, 0), (1, 0), (0, -1), (0, 1)] {
                    let nx = x + dx, ny = y + dy
                    guard nx >= 0, ny >= 0, nx < width, ny < height, filled[ny * width + nx] else { continue }
                    let o = (ny * width + nx) * 4
                    sum &+= SIMD3(Int(px[o]), Int(px[o + 1]), Int(px[o + 2]))
                    n += 1
                }
                if n > 0 {
                    let o = (y * width + x) * 4
                    out[o] = UInt8(sum.x / n); out[o + 1] = UInt8(sum.y / n); out[o + 2] = UInt8(sum.z / n)
                    next[y * width + x] = true
                }
            }
        }
        px = out
        filled = next
    }
}

func writePNG(_ px: [UInt8], width: Int, height: Int, to url: URL) {
    let provider = CGDataProvider(data: Data(px) as CFData)!
    let cg = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                     space: CGColorSpace(name: CGColorSpace.sRGB)!,
                     bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                     provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, cg, nil)
    precondition(CGImageDestinationFinalize(dest))
}

// MARK: - Sprite atlas

let cellW = 256, cellH = 512, cols = 8
let rows = (specs.count + cols - 1) / cols
let atlasW = cellW * cols, atlasH = cellH * rows
var atlas = [UInt8](repeating: 0, count: atlasW * atlasH * 4)
var spriteEntries: [[String: Any]] = []

for (i, spec) in specs.enumerated() {
    let m = model(spec.file, biome: spec.biomes[0])
    let scene = stage(fog: false)
    let node = m.node.clone()
    scene.rootNode.addChildNode(node)
    let aspect = Float(cellW) / Float(cellH)
    let half = max(m.size.y / 2, m.size.x / 2 / aspect) * 1.03
    let cam = orthoCamera(center: SIMD3(0, m.size.y / 2, 0), halfHeight: half)
    let px = render(scene, camera: cam, width: cellW, height: cellH)

    // Tight bounds of the opaque content within the cell.
    var minX = cellW, maxX = 0, minY = cellH, maxY = 0
    for y in 0..<cellH { for x in 0..<cellW where px[(y * cellW + x) * 4 + 3] > 8 {
        minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
    } }
    let ox = (i % cols) * cellW, oy = (i / cols) * cellH
    for y in 0..<cellH {
        let src = y * cellW * 4, dst = ((oy + y) * atlasW + ox) * 4
        atlas.replaceSubrange(dst..<(dst + cellW * 4), with: px[src..<(src + cellW * 4)])
    }
    let w = maxX - minX + 1, h = maxY - minY + 1
    spriteEntries.append([
        "name": spec.file,
        "biomes": spec.biomes,
        // Normalised atlas rect, origin top-left.
        "uv": [Double(ox + minX) / Double(atlasW), Double(oy + minY) / Double(atlasH),
               Double(w) / Double(atlasW), Double(h) / Double(atlasH)],
        "height": Double(spec.height),
        "aspect": Double(w) / Double(h),
    ])
    print("sprite \(spec.file) \(w)x\(h)")
}
dilate(&atlas, width: atlasW, height: atlasH, passes: 6)
writePNG(atlas, width: atlasW, height: atlasH, to: outDir.appendingPathComponent("tree-atlas.png"))

// MARK: - Forest walls

let wallWidth: Float = 120, wallHeight: Float = 30
let wallPxW = 2048, wallPxH = 512
var wallEntries: [String: Any] = [:]

for (b, biome) in biomes.enumerated() {
    var seed = UInt64(1234 + b * 77)
    func rand() -> Float {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        return Float(seed >> 33) / Float(1 << 31)
    }
    let pool = specs.filter { $0.biomes.contains(biome) }
    let trees = pool.filter { $0.height > 4 }
    let bushes = pool.filter { $0.height <= 4 }
    let scene = stage(fog: true)
    let density: Float = biome == "arid" ? 0.45 : 1

    func plant(_ spec: Spec, x: Float, z: Float, scale: Float) {
        let m = model(spec.file, biome: biome)
        let s = spec.height * scale / m.size.y
        let yaw = rand() * 2 * .pi
        // Copies either side make the strip tile seamlessly.
        for shift: Float in [-wallWidth, 0, wallWidth] {
            let n = m.node.clone()
            n.simdScale = SIMD3(repeating: s)
            n.simdPosition = SIMD3(x + shift, 0, z)
            n.simdEulerAngles.y = yaw
            scene.rootNode.addChildNode(n)
        }
    }

    // Back to front: tall dense rows, then mid rows, then underbrush.
    let rowsSpec: [(z: Float, count: Int, scale: ClosedRange<Float>)] = [
        (-40, 44, 1.15...1.5), (-32, 40, 1.05...1.4), (-24, 34, 1.0...1.3), (-16, 30, 0.9...1.2),
        (-9, 24, 0.85...1.15), (-3, 16, 0.7...1.05),
    ]
    for row in rowsSpec {
        let count = Int(Float(row.count) * density)
        for k in 0..<count {
            let x = (Float(k) + rand()) / Float(count) * wallWidth
            let spec = trees[Int(rand() * Float(trees.count)) % trees.count]
            let scale = row.scale.lowerBound + rand() * (row.scale.upperBound - row.scale.lowerBound)
            plant(spec, x: x, z: row.z + rand() * 5 - 2.5, scale: scale)
        }
    }
    if !bushes.isEmpty {
        for k in 0..<Int(40 * density) {
            let x = (Float(k) + rand()) / Float(Int(40 * density)) * wallWidth
            plant(bushes[Int(rand() * Float(bushes.count)) % bushes.count], x: x, z: 1 + rand() * 3,
                  scale: 0.8 + rand() * 0.8)
        }
    }

    let cam = orthoCamera(center: SIMD3(wallWidth / 2, wallHeight / 2, 0), halfHeight: wallHeight / 2, distance: 40)
    var px = render(scene, camera: cam, width: wallPxW, height: wallPxH)
    dilate(&px, width: wallPxW, height: wallPxH, passes: 6)
    let file = "forest-wall-\(biome).png"
    writePNG(px, width: wallPxW, height: wallPxH, to: outDir.appendingPathComponent(file))
    wallEntries[biome] = ["file": file, "width": Double(wallWidth), "height": Double(wallHeight)]
    print("wall \(biome)")
}

let manifest: [String: Any] = ["atlas": "tree-atlas.png", "sprites": spriteEntries, "walls": wallEntries,
                               "source": "Kenney Nature Kit (CC0)"]
let json = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
try json.write(to: outDir.appendingPathComponent("trees.json"))
print("wrote \(outDir.path)")
