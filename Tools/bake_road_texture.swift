import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

func tiled(_ image: CIImage) -> CIImage {
    let filter = CIFilter.affineTile()
    filter.inputImage = image
    filter.transform = .identity
    return filter.outputImage!
}

guard CommandLine.arguments.count == 3 else {
    fatalError("Usage: swift Tools/bake_road_texture.swift <source-color.jpg> <output.png>")
}
let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
guard let source = CIImage(contentsOf: sourceURL) else {
    fatalError("Cannot decode source texture")
}

let size = 1024
let extent = CGRect(x: 0, y: 0, width: size, height: size)
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
let context = CIContext(options: [.workingColorSpace: colorSpace])
let scaled = source.transformed(by: CGAffineTransform(
    scaleX: CGFloat(size) / source.extent.width,
    y: CGFloat(size) / source.extent.height
))
let surface = tiled(scaled)
    .applyingFilter("CIColorControls", parameters: [
        kCIInputSaturationKey: 0,
        kCIInputContrastKey: 0.85
    ])
    .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 0.65])
    .applyingFilter("CIMotionBlur", parameters: [
        kCIInputRadiusKey: 32,
        kCIInputAngleKey: Double.pi / 2
    ])
    .applyingFilter("CIColorMatrix", parameters: [
        "inputRVector": CIVector(x: 0.72, y: 0, z: 0, w: 0),
        "inputGVector": CIVector(x: 0, y: 0.70, z: 0, w: 0),
        "inputBVector": CIVector(x: 0, y: 0, z: 0.71, w: 0)
    ])
    .cropped(to: extent)

guard let paintContext = CGContext(data: nil, width: size, height: size,
    bitsPerComponent: 8, bytesPerRow: size * 4, space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    fatalError("Cannot create paint bitmap")
}
paintContext.setFillColor(CGColor(red: 0.88, green: 0.88, blue: 0.84, alpha: 1))
let lineWidth = CGFloat(size) * 0.15 / 11
for laneFraction in [CGFloat(1.0 / 3), CGFloat(2.0 / 3)] {
    for dashFraction in [CGFloat(0.125), CGFloat(0.625)] {
        paintContext.fill(CGRect(x: CGFloat(size) * laneFraction - lineWidth / 2,
                                 y: CGFloat(size) * dashFraction,
                                 width: lineWidth, height: CGFloat(size) * 0.25))
    }
}
let markings = tiled(CIImage(cgImage: paintContext.makeImage()!))
    .applyingFilter("CIMotionBlur", parameters: [
        kCIInputRadiusKey: 5,
        kCIInputAngleKey: Double.pi / 2
    ])
    .cropped(to: extent)
let road = markings.composited(over: surface)
try context.writePNGRepresentation(of: road, to: outputURL, format: .RGBA8,
                                   colorSpace: colorSpace)
print("Baked 1024px road strip: directional asphalt grain, two dashed lines, 11m x 12m")