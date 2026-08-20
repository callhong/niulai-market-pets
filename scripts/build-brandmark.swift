import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Resources/BrandMark.ico")
let sizes = [16, 24, 32, 48, 64, 128, 256]

func path(_ points: [(CGFloat, CGFloat)], closed: Bool = true) -> CGPath {
    let p = CGMutablePath()
    guard let first = points.first else { return p }
    p.move(to: CGPoint(x: first.0, y: first.1))
    for point in points.dropFirst() { p.addLine(to: CGPoint(x: point.0, y: point.1)) }
    if closed { p.closeSubpath() }
    return p
}

func drawMark(in context: CGContext, size: CGFloat) {
    let s = size / 256
    context.saveGState()
    context.scaleBy(x: s, y: s)
    context.setFillColor(CGColor(gray: 0, alpha: 1))
    context.setStrokeColor(CGColor(gray: 0, alpha: 1))
    context.setLineCap(.round)
    context.setLineJoin(.round)

    func fill(_ points: [(CGFloat, CGFloat)], width: CGFloat = 0) {
        let p = path(points)
        context.addPath(p)
        context.setLineWidth(width)
        context.drawPath(using: width > 0 ? .fillStroke : .fill)
    }

    fill([(71, 86), (37, 76), (22, 55), (32, 32), (55, 37), (75, 58)])
    fill([(185, 86), (219, 76), (234, 55), (224, 32), (201, 37), (181, 58)])
    fill([(64, 67), (45, 40), (50, 18), (70, 12), (84, 70)])
    fill([(192, 67), (211, 40), (206, 18), (186, 12), (172, 70)])
    fill([(58, 82), (66, 48), (94, 25), (128, 25), (162, 25), (190, 48), (198, 82), (188, 174), (176, 209), (128, 232), (80, 209), (68, 174)])
    fill([(82, 143), (100, 127), (128, 125), (156, 127), (174, 143), (180, 164), (174, 185), (162, 196), (128, 204), (94, 196), (82, 185), (76, 164)])
    context.restoreGState()
}

func pngData(size: Int) -> Data {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bytesPerRow = size * 4
    let context = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.clear(CGRect(x: 0, y: 0, width: size, height: size))
    drawMark(in: context, size: CGFloat(size))
    let image = context.makeImage()!
    let data = NSMutableData()
    let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    precondition(CGImageDestinationFinalize(destination))
    return data as Data
}

var pngs = [(Int, Data)]()
for size in sizes { pngs.append((size, pngData(size: size))) }

var ico = Data()
func appendUInt16(_ value: UInt16) { ico.append(UInt8(value & 0xff)); ico.append(UInt8(value >> 8)) }
func appendUInt32(_ value: UInt32) {
    appendUInt16(UInt16(value & 0xffff)); appendUInt16(UInt16(value >> 16))
}
appendUInt16(0); appendUInt16(1); appendUInt16(UInt16(pngs.count))
let headerSize = 6 + pngs.count * 16
var offset = headerSize
for (size, data) in pngs {
    ico.append(UInt8(size == 256 ? 0 : size))
    ico.append(UInt8(size == 256 ? 0 : size))
    ico.append(0); ico.append(0)
    appendUInt16(1); appendUInt16(32)
    appendUInt32(UInt32(data.count)); appendUInt32(UInt32(offset))
    offset += data.count
}
for (_, data) in pngs { ico.append(data) }
try ico.write(to: output, options: .atomic)
print(output.path)
