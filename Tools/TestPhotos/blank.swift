import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// 不联网造几张纯色渐变照片，给自动测试用。usage: blank <outDir> <file>...
let args = CommandLine.arguments
for (i, file) in args.dropFirst(2).enumerated() {
    let (w, h) = (800, 600)
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    let hue = Double(i) / Double(max(args.count - 2, 1))
    func rgb(_ h: Double, _ l: Double) -> CGColor {
        let r = 0.5 + 0.5 * cos(2 * .pi * (h + 0.0)), g = 0.5 + 0.5 * cos(2 * .pi * (h + 0.33)), b = 0.5 + 0.5 * cos(2 * .pi * (h + 0.66))
        return CGColor(red: r * l, green: g * l, blue: b * l, alpha: 1)
    }
    let gradient = CGGradient(colorsSpace: nil, colors: [rgb(hue, 0.95), rgb(hue + 0.1, 0.55)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: w, y: h), options: [])
    let url = URL(fileURLWithPath: "\(args[1])/\(file)")
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
    CGImageDestinationFinalize(dest)
}
