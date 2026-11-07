import AppKit
import SceneKit
import simd

typealias UIColor = NSColor

@main
struct PropPlacementCheck {
    static func main() {
        let path = TrackPath()
        checkCarScale()
        checkRoad(path)
        let root = SCNNode()
        TrackDecorations.addDecorations(to: root, path: path)
        precondition(!root.childNodes.isEmpty, "Prop resources are missing from the test bundle")

        for node in root.childNodes {
            let bounds = node.boundingBox
            let groundCenter = SIMD3<Float>(
                Float(bounds.min.x + bounds.max.x) * 0.5,
                Float(bounds.min.y),
                Float(bounds.min.z + bounds.max.z) * 0.5
            )
            precondition(simd_length(groundCenter) < 0.001,
                         "\(node.name ?? "unknown") is not ground-centered")
            let up = simd_normalize(node.simdConvertVector(SIMD3<Float>(0, 1, 0), to: nil))
            precondition(simd_distance(up, SIMD3<Float>(0, 1, 0)) < 0.001)
        }

        let arches = root.childNodes.filter { $0.name == "overhead" }
        precondition(arches.count == 1)
        check(arches[0], sample: path.samples[0], offset: 0, forward: path.samples[0].forward)
        let archWidth = Float(arches[0].boundingBox.max.x - arches[0].boundingBox.min.x)
            * arches[0].simdScale.x
        precondition(abs(archWidth - 13.86) < 0.01)
        let archAcross = simd_normalize(arches[0].simdConvertVector(SIMD3<Float>(1, 0, 0), to: nil))
        precondition(simd_distance(archAcross, path.samples[0].right) < 0.001)

        let barriers = root.childNodes.filter { $0.name == "barrierRed" }
        let barrierSamples = Array(stride(from: 0, to: path.samples.count, by: 4))
        precondition(barriers.count == barrierSamples.count * 2)
        for (pair, sampleIndex) in barrierSamples.enumerated() {
            let sample = path.samples[sampleIndex]
            for side in 0..<2 {
                let node = barriers[pair * 2 + side]
                let offset = (sample.halfWidth + 2.5) * (side == 0 ? Float(1) : -1)
                check(node, sample: sample, offset: offset, forward: sample.forward)
                let bounds = node.boundingBox
                precondition(bounds.max.z - bounds.min.z > bounds.max.x - bounds.min.x,
                             "Barrier length must follow local -Z")
            }
        }

        let lamps = root.childNodes.filter { $0.name == "lightPostLarge" }
        let lampSamples = Array(stride(from: 0, to: path.samples.count, by: 10))
        precondition(lamps.count == lampSamples.count * 2)
        for (pair, sampleIndex) in lampSamples.enumerated() {
            let sample = path.samples[sampleIndex]
            check(lamps[pair * 2], sample: sample, offset: sample.halfWidth + 1.5, forward: -sample.right)
            check(lamps[pair * 2 + 1], sample: sample, offset: -(sample.halfWidth + 1.5), forward: sample.right)
        }

        let grandstands = root.childNodes.filter { $0.name == "grandStandCovered" }
        let standSamples = stride(from: 20, to: path.samples.count, by: 20).filter {
            (($0 - 20) / 20) % 3 != 2
        }
        precondition(grandstands.count == standSamples.count * 2)
        for (pair, sampleIndex) in standSamples.enumerated() {
            let sample = path.samples[sampleIndex]
            check(grandstands[pair * 2], sample: sample, offset: 24, forward: -sample.right)
            check(grandstands[pair * 2 + 1], sample: sample, offset: -24, forward: sample.right)
        }
        print("PASS: \(root.childNodes.count) ground-centered props; centered transverse arch; \(barriers.count) tangent-aligned barriers; \(lamps.count) inward lamps; \(grandstands.count) inward grandstands")
    }

    private static func checkCarScale() {
        let styles: [CarStyle] = [.truckGreen, .truckPurple, .truckRed, .truckYellow]
        for style in styles {
            let car = CarNode(style: style)
            let bounds = car.boundingBox
            let width = Float(bounds.max.x - bounds.min.x)
            let length = Float(bounds.max.z - bounds.min.z)
            let expectedLength: Float = style == .truckGreen ? 4.064 : 3.92
            precondition(abs(width - 2.1) < 0.01, "Incorrect truck width: \(style)")
            precondition(abs(length - expectedLength) < 0.02, "Incorrect truck length: \(style)")
            precondition(abs(Float(bounds.min.y) + 0.4) < 0.001,
                         "Truck no longer grounded: \(style)")
            precondition(width < (11.0 / 3.0) * 0.6, "Truck too wide for a lane")
        }
        print("PASS: four trucks measure 2.10m wide / 3.92-4.06m long and remain grounded")
    }

    private static func checkRoad(_ path: TrackPath) {
        let track = TrackMeshBuilder.buildTrackNode(path: path)
        let geometry = track.childNode(withName: "trackMesh", recursively: false)!.geometry!
        let vertices = geometry.sources(for: .vertex)[0]
        let coordinates = geometry.sources(for: .texcoord)[0]
        let roadElement = geometry.elements[0]
        let indices = roadElement.data.withUnsafeBytes { bytes in
            stride(from: 0, to: roadElement.data.count, by: roadElement.bytesPerIndex).map {
                Int(bytes.loadUnaligned(fromByteOffset: $0, as: UInt32.self))
            }
        }
        var upwardTriangles = 0
        for triangle in stride(from: 0, to: indices.count, by: 3) {
            let points = indices[triangle..<(triangle + 3)].map { vertex in
                SIMD3<Float>(Float(component(vertices, vertex: vertex, axis: 0)),
                             Float(component(vertices, vertex: vertex, axis: 1)),
                             Float(component(vertices, vertex: vertex, axis: 2)))
            }
            if abs(points[0].y - points[1].y) < 0.001
                && abs(points[0].y - points[2].y) < 0.001 {
                let faceNormal = simd_cross(points[1] - points[0], points[2] - points[0])
                precondition(faceNormal.y > 0, "Road triangle faces downward")
                upwardTriangles += 1
            }
        }
        precondition(upwardTriangles == path.samples.count * 4)
        let columns = vertices.vectorCount / (path.samples.count + 1)
        precondition(columns == 17)
        precondition(coordinates.vectorCount == vertices.vectorCount)
        let lastRow = path.samples.count * columns
        let repeatCount = component(coordinates, vertex: lastRow, axis: 1)
        precondition(abs(repeatCount - repeatCount.rounded()) < 0.0001)
        let tileSize = Double(path.totalLength) / repeatCount
        precondition(abs(tileSize - 12) < 0.1)
        for column in 0..<columns {
            for axis in 0..<3 {
                precondition(component(vertices, vertex: column, axis: axis)
                    == component(vertices, vertex: lastRow + column, axis: axis))
            }
            precondition(component(coordinates, vertex: column, axis: 0)
                == component(coordinates, vertex: lastRow + column, axis: 0))
        }
        let roadWidthUV = component(coordinates, vertex: 9, axis: 0)
            - component(coordinates, vertex: 7, axis: 0)
        precondition(abs(roadWidthUV - 1) < 0.001)
        precondition(abs(component(coordinates, vertex: 7, axis: 0)) < 0.001)
        for row in 0..<path.samples.count {
            let delta = component(coordinates, vertex: (row + 1) * columns, axis: 1)
                - component(coordinates, vertex: row * columns, axis: 1)
            precondition(delta > 0 && delta < 1, "Discontinuous road UVs")
        }
        let material = geometry.materials[0]
        precondition(material.lightingModel == .physicallyBased)
        let property = material.diffuse
        guard let url = property.contents as? URL,
              let data = try? Data(contentsOf: url),
              let image = NSBitmapImageRep(data: data) else {
            preconditionFailure("Road strip missing or unreadable")
        }
        precondition(image.pixelsWide == 1024 && image.pixelsHigh == 1024)
        precondition(property.wrapS == .clamp && property.wrapT == .repeat)
        precondition(property.mipFilter == .linear && property.maxAnisotropy == 16)
        for column in [341, 683] {
            let paint = image.colorAt(x: column, y: 256)!.usingColorSpace(.deviceRGB)!
            let gap = image.colorAt(x: column, y: 512)!.usingColorSpace(.deviceRGB)!
            precondition(paint.redComponent > 0.7 && gap.redComponent < 0.55,
                         "Missing dashed lane marking")
        }
        print("PASS: \(upwardTriangles) upward road triangles; full-width road strip; two dashed lane lines; 12m repeat; continuous lap seam")
    }

    private static func component(_ source: SCNGeometrySource, vertex: Int, axis: Int) -> Double {
        let offset = source.dataOffset + vertex * source.dataStride + axis * source.bytesPerComponent
        return source.data.withUnsafeBytes { bytes in
            if source.bytesPerComponent == 4 {
                return Double(bytes.loadUnaligned(fromByteOffset: offset, as: Float.self))
            }
            return bytes.loadUnaligned(fromByteOffset: offset, as: Double.self)
        }
    }

    private static func check(_ node: SCNNode, sample: PathSample, offset: Float,
                              forward: SIMD3<Float>) {
        let expected = sample.position + sample.right * offset
        precondition(simd_distance(node.simdPosition, expected) < 0.001,
                     "Incorrect placement for \(node.name ?? "unknown")")
        let actual = simd_normalize(node.simdConvertVector(SIMD3<Float>(0, 0, -1), to: nil))
        precondition(simd_distance(actual, forward) < 0.001,
                     "Incorrect facing for \(node.name ?? "unknown")")
    }
}