// Draw the app icon: a graphite rounded square with three bars, matching the panel's readout.
//
// Run through scripts/make-icon.sh, which turns the PNG into the .icns the bundle carries, so the
// icon is reproducible from source instead of being a binary nobody can edit.
//
//   swift scripts/make-icon.swift <output.png>

import AppKit
import CoreGraphics
import Foundation

let side = 1024.0
let output = URL(
  fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png")

let space = CGColorSpaceCreateDeviceRGB()
guard
  let context = CGContext(
    data: nil, width: Int(side), height: Int(side), bitsPerComponent: 8, bytesPerRow: 0,
    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
else {
  FileHandle.standardError.write(Data("cannot create the drawing context\n".utf8))
  exit(1)
}

// macOS icons leave a margin and round the corners by about 22.5%.
let inset = side * 0.06
let square = CGRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2)
let radius = square.width * 0.225
context.addPath(
  CGPath(roundedRect: square, cornerWidth: radius, cornerHeight: radius, transform: nil))
context.clip()

// Graphite, a shade lighter at the top so the square reads as a surface rather than a hole.
let background = [
  CGColor(red: 0.23, green: 0.23, blue: 0.26, alpha: 1),
  CGColor(red: 0.10, green: 0.10, blue: 0.12, alpha: 1),
] as CFArray
if let gradient = CGGradient(colorsSpace: space, colors: background, locations: [0, 1]) {
  context.drawLinearGradient(
    gradient, start: CGPoint(x: 0, y: side), end: CGPoint(x: 0, y: 0), options: [])
}

// Three bars, rising: the sparkline the panel draws, in the ember tone.
context.setFillColor(CGColor(red: 0.91, green: 0.51, blue: 0.23, alpha: 1))
let barWidth = square.width * 0.155
let gap = square.width * 0.085
let baseline = square.minY + square.height * 0.15
let heights = [0.30, 0.55, 0.78].map { square.height * $0 }
let left = square.midX - (barWidth * 1.5 + gap)

for (index, height) in heights.enumerated() {
  let bar = CGRect(
    x: left + CGFloat(index) * (barWidth + gap), y: baseline, width: barWidth, height: height)
  context.addPath(
    CGPath(roundedRect: bar, cornerWidth: barWidth / 2, cornerHeight: barWidth / 2, transform: nil))
}
context.fillPath()

guard let image = context.makeImage() else {
  FileHandle.standardError.write(Data("cannot render the image\n".utf8))
  exit(1)
}
guard let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
else {
  FileHandle.standardError.write(Data("cannot encode the PNG\n".utf8))
  exit(1)
}
try data.write(to: output)
print("wrote \(output.path)")
