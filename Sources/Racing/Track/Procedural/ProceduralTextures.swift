import UIKit
import simd

/// CPU-generated, tileable textures. Everything is seeded so tracks look identical every launch.
enum ProceduralTextures {

    // MARK: - Image plumbing

    /// Renders `shade(u, v)` (u, v in [0, 1)) into an sRGB image, rows in parallel.
    static func image(width: Int, height: Int, _ shade: (Float, Float) -> SIMD3<Float>) -> UIImage {
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        pixels.withUnsafeMutableBufferPointer { buf in
            let base = buf.baseAddress!
            DispatchQueue.concurrentPerform(iterations: height) { y in
                let v = (Float(y) + 0.5) / Float(height)
                for x in 0..<width {
                    let c = simd_clamp(shade((Float(x) + 0.5) / Float(width), v), .zero, SIMD3(repeating: 1))
                    let o = (y * width + x) * 4
                    base[o] = UInt8(c.x * 255)
                    base[o + 1] = UInt8(c.y * 255)
                    base[o + 2] = UInt8(c.z * 255)
                }
            }
        }
        let data = Data(pixels) as CFData
        let cg = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                         bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                         bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                         provider: CGDataProvider(data: data)!, decode: nil,
                         shouldInterpolate: true, intent: .defaultIntent)!
        return UIImage(cgImage: cg)
    }

    /// Tangent-space normal map from a tileable height function.
    static func normalMap(size: Int, strength: Float, _ height: (Float, Float) -> Float) -> UIImage {
        let e = 1 / Float(size)
        return image(width: size, height: size) { u, v in
            let dx = height(u + e, v) - height(u - e, v)
            let dy = height(u, v + e) - height(u, v - e)
            let n = simd_normalize(SIMD3(-dx * strength, -dy * strength, 1))
            return n * 0.5 + 0.5
        }
    }

    // MARK: - Terrain

    static func grass(_ p: TrackDefinition.Palette, seed: UInt64) -> UIImage {
        let n = Noise2D(seed: seed)
        return image(width: 512, height: 512) { u, v in
            let patch = n.fbm(u * 4, v * 4, octaves: 4, period: 4) * 0.5 + 0.5
            let blades = n.fbm(u * 96, v * 96, octaves: 2, period: 96)
            let speck = n.noise(u * 220, v * 220, period: 220)
            var c = simd_mix(p.grassA, p.grassB, SIMD3(repeating: smoothstep(0.3, 0.75, patch)))
            c *= 0.86 + blades * 0.22 + speck * 0.08
            return c
        }
    }

    static func rock(_ p: TrackDefinition.Palette, seed: UInt64) -> UIImage {
        let n = Noise2D(seed: seed)
        return image(width: 512, height: 512) { u, v in
            let r = n.ridged(u * 6, v * 6, octaves: 5, period: 6)
            let f = n.fbm(u * 3, v * 3, octaves: 4, period: 3)
            let strata = sin((v * 18 + f * 2.5) * .pi * 2) * 0.5 + 0.5
            var c = simd_mix(p.rockA, p.rockB, SIMD3(repeating: smoothstep(0.2, 0.9, r)))
            c *= 0.78 + strata * 0.14 + n.noise(u * 128, v * 128, period: 128) * 0.1
            let crack = smoothstep(0.08, 0.0, abs(n.fbm(u * 8, v * 8, octaves: 3, period: 8)))
            return c * (1 - crack * 0.45)
        }
    }

    static func sand(_ p: TrackDefinition.Palette, seed: UInt64) -> UIImage {
        let n = Noise2D(seed: seed)
        return image(width: 512, height: 512) { u, v in
            let ripple = sin((v * 24 + n.fbm(u * 4, v * 4, octaves: 3, period: 4) * 3) * .pi * 2)
            let grain = n.noise(u * 256, v * 256, period: 256)
            let patch = n.fbm(u * 3, v * 3, octaves: 3, period: 3)
            return p.sand * (0.92 + ripple * 0.035 + grain * 0.07 + patch * 0.12)
        }
    }

    /// Square paving slabs / cobbles for town pavements.
    static func pavement(seed: UInt64) -> UIImage {
        let n = Noise2D(seed: seed)
        return image(width: 512, height: 512) { u, v in
            let cell = n.cellular(u * 12, v * 12, cells: 12)
            let edge = smoothstep(0.02, 0.10, cell.f2 - cell.f1)
            let tone = Float(cell.id & 31) / 31
            let grain = n.noise(u * 200, v * 200, period: 200) * 0.06
            let stone = SIMD3<Float>(0.56, 0.54, 0.50) * (0.82 + tone * 0.3 + grain)
            return simd_mix(SIMD3(0.24, 0.23, 0.22), stone, SIMD3(repeating: edge))
        }
    }

    // MARK: - Road

    static func gravel(seed: UInt64, tint: SIMD3<Float> = SIMD3(0.58, 0.54, 0.48)) -> UIImage {
        let n = Noise2D(seed: seed)
        return image(width: 512, height: 512) { u, v in
            let c1 = n.cellular(u * 48, v * 48, cells: 48)
            let pebble = smoothstep(0.0, 0.25, c1.f2 - c1.f1)
            let tone = Float(c1.id & 15) / 15
            let base = tint * (0.7 + tone * 0.45)
            return simd_mix(tint * 0.45, base, SIMD3(repeating: pebble))
                * (0.95 + n.fbm(u * 4, v * 4, octaves: 3, period: 4) * 0.15)
        }
    }

    /// Dirt road across u (0 = left edge, 1 = right edge) with tyre ruts; v runs along the track.
    static func dirtRoad(seed: UInt64) -> UIImage {
        let n = Noise2D(seed: seed)
        let base = SIMD3<Float>(0.52, 0.38, 0.24)
        return image(width: 512, height: 1024) { u, v in
            let wobble = n.fbm(v * 6, 0.5, octaves: 3, period: 6) * 0.03
            let x = u + wobble
            let rut = max(exp(-pow((x - 0.30) / 0.05, 2)), exp(-pow((x - 0.70) / 0.05, 2)))
            let edge = smoothstep(0.06, 0.0, min(x, 1 - x))
            let stones = n.cellular(u * 40, v * 80, cells: 40)
            let pebble = smoothstep(0.12, 0.0, stones.f1) * 0.25
            let f = n.fbm(u * 8, v * 16, octaves: 4, period: 8)
            var c = base * (0.92 + f * 0.22 - rut * 0.20 + pebble)
            c = simd_mix(c, SIMD3(0.40, 0.36, 0.22), SIMD3(repeating: edge * 0.6))
            return c
        }
    }

    /// Red/white kerb stripes: 8 blocks per texture repeat along v.
    static func kerb() -> UIImage {
        let n = Noise2D(seed: 5)
        return image(width: 64, height: 512) { u, v in
            let stripe = Int(v * 8) % 2 == 0
            let base: SIMD3<Float> = stripe ? SIMD3(0.82, 0.12, 0.10) : SIMD3(0.92, 0.92, 0.90)
            let dirt = n.fbm(u * 4, v * 32, octaves: 3, period: 4) * 0.08
            let gap = smoothstep(0.004, 0.0, abs(v * 8 - (v * 8).rounded()))
            return base * (0.95 + dirt) * (1 - gap * 0.4)
        }
    }

    // MARK: - Structures

    /// Concrete panels for tunnels and portals; one texture tile = 4 × 4 m.
    static func concrete(seed: UInt64) -> UIImage {
        let n = Noise2D(seed: seed)
        return image(width: 512, height: 512) { u, v in
            let f = n.fbm(u * 6, v * 6, octaves: 5, period: 6)
            let streak = n.fbm(u * 40, v * 2, octaves: 2, period: 40) * smoothstep(0.3, 1, v)
            let joint = smoothstep(0.006, 0.0, min(abs(u - 0.5), min(u, 1 - u)))
                + smoothstep(0.006, 0.0, min(v, 1 - v))
            let c = SIMD3<Float>(0.66, 0.65, 0.62) * (0.9 + f * 0.18 - streak * 0.12)
            return c * (1 - min(joint, 1) * 0.35)
        }
    }

    /// One facade tile = 2 bays × 1 floor (6 m × 3 m). Upper floors with window variations.
    static func facade(wall: SIMD3<Float>, seed: UInt64) -> UIImage {
        let n = Noise2D(seed: seed)
        var rng = SplitMix64(seed: seed)
        let shutters = rng.float() > 0.5
        let shutterColor = SIMD3<Float>(rng.float(0.15...0.4), rng.float(0.25...0.45), rng.float(0.2...0.35))
        let lit = (rng.float(), rng.float())
        let variant = Int(rng.next() % 3)
        return image(width: 512, height: 256) { u, v in
            let plaster = n.fbm(u * 8, v * 4, octaves: 4, period: 8)
            let grime = smoothstep(0.6, 1, v) * n.fbm(u * 3, v * 2, octaves: 2, period: 3) * 0.08
            var c = wall * (0.9 + plaster * 0.14 - grime)
            let bay = u < 0.5 ? 0 : 1
            let lu = (u * 2).truncatingRemainder(dividingBy: 1)
            let lv = 1 - v
            let inWindow = lu > 0.3 && lu < 0.7 && lv > 0.28 && lv < 0.8
            let inFrame = lu > 0.27 && lu < 0.73 && lv > 0.25 && lv < 0.83
            if inFrame && !inWindow {
                if variant == 0 {
                    let keystone = smoothstep(0.08, 0.0, abs(lu - 0.5)) * smoothstep(0.06, 0.02, abs(lv - 0.79))
                    c = simd_mix(SIMD3(0.92, 0.91, 0.88), SIMD3(0.85, 0.82, 0.78), SIMD3(repeating: keystone))
                } else if variant == 1 {
                    let lintel = smoothstep(0.01, 0.0, abs(lv - 0.81))
                    c = simd_mix(SIMD3(0.92, 0.91, 0.88), SIMD3(0.78, 0.75, 0.70), SIMD3(repeating: lintel))
                } else {
                    c = SIMD3(0.92, 0.91, 0.88)
                }
            }
            if inWindow {
                let reflect = smoothstep(0.28, 0.8, lv) * 0.25 + (lu - 0.3) * 0.2
                let warm = (bay == 0 ? lit.0 : lit.1) > 0.75
                c = warm ? SIMD3(0.85, 0.72, 0.45) : SIMD3(0.16, 0.22, 0.28) + reflect
                let mullion = abs(lu - 0.5) < 0.012 || abs(lv - 0.58) < 0.012
                if mullion { c = SIMD3(0.88, 0.88, 0.86) }
                let sill = smoothstep(0.02, 0.0, abs(lv - 0.28))
                c = simd_mix(c, SIMD3(0.82, 0.78, 0.72), SIMD3(repeating: sill * 0.6))
            }
            if shutters && lv > 0.25 && lv < 0.83 && ((lu > 0.16 && lu < 0.27) || (lu > 0.73 && lu < 0.84)) {
                let slat = sin(lv * 160) * 0.5 + 0.5
                c = shutterColor * (0.85 + slat * 0.2)
            }
            if lv < 0.04 { c *= 0.75 }
            return c
        }
    }

    /// Ground floor, one tile = 2 bays × 3.6 m. Bay 0 (0–3 m): shop window or house window;
    /// bay 1 (3–6 m): door centred at 4.5 m, 1.1 m wide, 2.45 m tall.
    static func groundFloor(wall: SIMD3<Float>, shop: Bool, seed: UInt64) -> UIImage {
        let n = Noise2D(seed: seed)
        var rng = SplitMix64(seed: seed)
        let fascia = SIMD3<Float>(rng.float(0.05...0.45), rng.float(0.08...0.3), rng.float(0.1...0.4))
        let wood = SIMD3<Float>(rng.float(0.25...0.5), rng.float(0.14...0.28), rng.float(0.08...0.16))
        let stone = SIMD3<Float>(0.70, 0.67, 0.62)
        let frame = SIMD3<Float>(0.9, 0.89, 0.86)
        return image(width: 512, height: 308) { u, v in
            let x = u * 6, y = (1 - v) * 3.6           // metres; y up from floor level
            let grain = n.noise(u * 64, v * 40, period: 64) * 0.06
            var c = wall * (0.86 + n.fbm(u * 8, v * 5, octaves: 3, period: 8) * 0.12)
            if shop {
                if y < 0.35 { c = stone * (0.9 + grain) }
                if y > 2.85 && y < 3.4 {
                    c = fascia * (0.9 + grain)
                    if y < 2.9 || y > 3.35 { c = frame * 0.8 }
                    // Lettering suggestion: light blocks centred on the fascia.
                    if abs(y - 3.12) < 0.09 && abs(x - 3) < 1.6 && Int(x * 4) % 3 != 0 { c = SIMD3(0.95, 0.92, 0.8) }
                }
                if x > 0.25 && x < 2.75 && y > 0.35 && y < 2.75 {
                    let inner = x > 0.33 && x < 2.67 && y > 0.43 && y < 2.67
                    if inner {
                        let shelf = (Int((y - 0.43) / 0.45) % 2 == 0) ? 0.9 : 1.1
                        c = SIMD3(0.20, 0.25, 0.30) * Float(shelf) + smoothstep(0.43, 2.6, y) * 0.18
                        if abs(x - 1.5) < 0.03 { c = wood * 0.7 }
                    } else {
                        c = wood * 0.7
                    }
                }
            } else {
                // Rusticated stone ground floor.
                c = stone * (0.88 + grain + n.fbm(u * 6, v * 4, octaves: 3, period: 6) * 0.1)
                let course = y.truncatingRemainder(dividingBy: 0.45)
                if course < 0.04 { c *= 0.7 }
                if x > 0.9 && x < 2.1 && y > 0.9 && y < 2.4 {
                    let inner = x > 0.98 && x < 2.02 && y > 0.98 && y < 2.32
                    c = inner ? SIMD3(0.18, 0.23, 0.28) + smoothstep(0.98, 2.3, y) * 0.2 : frame
                    if inner && (abs(x - 1.5) < 0.025 || abs(y - 1.9) < 0.025) { c = frame }
                }
            }
            // Door with surround, panels and fanlight.
            let dx = abs(x - 4.5)
            if dx < 0.7 && y < 2.65 {
                c = shop ? wood * 0.7 : stone * 1.08
                if dx < 0.55 && y < 2.45 {
                    c = wood * (0.85 + n.fbm(u * 6, v * 30, octaves: 2, period: 6) * 0.2)
                    if y > 2.05 { c = SIMD3(0.22, 0.27, 0.32) + (y - 2.05) * 0.3 }
                    let panel = dx > 0.08 && dx < 0.45 && ((y > 0.25 && y < 0.95) || (y > 1.15 && y < 1.9))
                    if !panel && y <= 2.05 { c *= 0.82 }
                    if abs(dx - 0.42) < 0.03 && abs(y - 1.05) < 0.04 { c = SIMD3(0.8, 0.7, 0.35) }
                }
            }
            return c
        }
    }

    /// Striped canvas for shop awnings; stripes run down the slope (u).
    static func awning(seed: UInt64) -> UIImage {
        var rng = SplitMix64(seed: seed)
        let a = SIMD3<Float>(rng.float(0.5...0.85), rng.float(0.05...0.3), rng.float(0.05...0.35))
        return image(width: 128, height: 32) { u, _ in
            Int(u * 8) % 2 == 0 ? a : SIMD3(0.93, 0.92, 0.88)
        }
    }

    /// Stone trim/cornice color for architectural details. Tileable.
    static func stoneTrim(seed: UInt64) -> UIImage {
        let n = Noise2D(seed: seed)
        return image(width: 256, height: 128) { u, v in
            let stone = SIMD3<Float>(0.80, 0.77, 0.71)
            let f = n.fbm(u * 6, v * 6, octaves: 3, period: 6)
            let pore = n.noise(u * 48, v * 48, period: 48) * 0.08
            return stone * (0.85 + f * 0.22 + pore)
        }
    }

    /// Slate roof tiles variant; one tile = 4 × 4 m.
    static func slateRoof(seed: UInt64) -> UIImage {
        let n = Noise2D(seed: seed)
        return image(width: 256, height: 256) { u, v in
            let rows: Float = 16
            let row = Int(v * rows)
            let offset: Float = row % 2 == 0 ? 0 : 0.5
            let cols: Float = 12
            let cu = (u * cols + offset).truncatingRemainder(dividingBy: 1)
            let cv = (v * rows).truncatingRemainder(dividingBy: 1)
            let tileVar = Float(n.hash(Int(u * cols + offset) & 255, row) & 7) / 7
            let edge = smoothstep(0.95, 1, cu) * 0.35 + smoothstep(0.94, 1, cv) * 0.25
            let color = SIMD3<Float>(0.32, 0.35, 0.38)
            return color * (0.65 + tileVar * 0.3 - edge * 0.2) * (0.95 + n.noise(u * 72, v * 72, period: 72) * 0.08)
        }
    }

    /// Clay or slate roof tiles; one tile = 4 × 4 m.
    static func roof(color: SIMD3<Float>, seed: UInt64) -> UIImage {
        let n = Noise2D(seed: seed)
        return image(width: 256, height: 256) { u, v in
            let rows: Float = 14
            let row = Int(v * rows)
            let offset: Float = row % 2 == 0 ? 0 : 0.5
            let cols: Float = 10
            let cu = (u * cols + offset).truncatingRemainder(dividingBy: 1)
            let cv = (v * rows).truncatingRemainder(dividingBy: 1)
            let tileTone = Float(n.hash(Int(u * cols + offset) & 255, row) & 15) / 15
            let shade = 0.7 + cv * 0.35 - smoothstep(0.92, 1, cu) * 0.3
            return color * (shade + tileTone * 0.16) * (0.95 + n.noise(u * 64, v * 64, period: 64) * 0.08)
        }
    }

    static func flatRoof(seed: UInt64) -> UIImage {
        let n = Noise2D(seed: seed)
        return image(width: 256, height: 256) { u, v in
            SIMD3<Float>(0.42, 0.41, 0.40) * (0.85 + n.fbm(u * 8, v * 8, octaves: 4, period: 8) * 0.25)
        }
    }

    static func bark(seed: UInt64) -> UIImage {
        let n = Noise2D(seed: seed)
        return image(width: 128, height: 256) { u, v in
            let ridges = n.fbm(u * 12, v * 2, octaves: 3, period: 12)
            return SIMD3<Float>(0.32, 0.24, 0.18) * (0.8 + ridges * 0.4)
        }
    }

    static func foliage(seed: UInt64) -> UIImage {
        let n = Noise2D(seed: seed)
        return image(width: 256, height: 256) { u, v in
            let c = n.cellular(u * 16, v * 16, cells: 16)
            let leaf = smoothstep(0.5, 0.05, c.f1)
            return SIMD3(repeating: 0.6 + leaf * 0.5 + n.noise(u * 64, v * 64, period: 64) * 0.1)
        }
    }

    static func waterNormal(seed: UInt64) -> UIImage {
        let n = Noise2D(seed: seed)
        return normalMap(size: 512, strength: 6) { u, v in
            let wu = u - u.rounded(.down), wv = v - v.rounded(.down)
            return n.fbm(wu * 8, wv * 8, octaves: 4, period: 8)
                + sin((wu + n.fbm(wu * 2, wv * 2, octaves: 2, period: 2) * 0.3) * .pi * 2 * 6) * 0.15
        }
    }
}
