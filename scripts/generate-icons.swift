#!/usr/bin/env swift

import Cocoa

// Generate app icon with waveform design
func generateAppIcon(size: Int) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    
    image.lockFocus()
    
    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    let cornerRadius = CGFloat(size) * 0.22
    
    // Background gradient (purple to blue)
    let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
    
    let gradient = NSGradient(colors: [
        NSColor(red: 0.55, green: 0.35, blue: 0.95, alpha: 1.0),  // Purple
        NSColor(red: 0.35, green: 0.45, blue: 0.95, alpha: 1.0)   // Blue
    ])!
    gradient.draw(in: path, angle: -45)
    
    // Draw waveform
    let waveColor = NSColor.white
    waveColor.setStroke()
    
    let centerY = CGFloat(size) / 2
    let lineWidth = CGFloat(size) * 0.06
    let barWidth = CGFloat(size) * 0.08
    let spacing = CGFloat(size) * 0.12
    let startX = CGFloat(size) * 0.2
    
    // Bar heights as percentages of size
    let heights: [CGFloat] = [0.15, 0.35, 0.5, 0.35, 0.15]
    
    for (index, heightPct) in heights.enumerated() {
        let barHeight = CGFloat(size) * heightPct
        let x = startX + CGFloat(index) * spacing
        
        let barPath = NSBezierPath()
        barPath.lineWidth = barWidth
        barPath.lineCapStyle = .round
        barPath.move(to: NSPoint(x: x, y: centerY - barHeight/2))
        barPath.line(to: NSPoint(x: x, y: centerY + barHeight/2))
        barPath.stroke()
    }
    
    image.unlockFocus()
    return image
}

func savePNG(_ image: NSImage, to path: String) {
    guard let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData),
          let pngData = bitmap.representation(using: .png, properties: [:]) else {
        print("Failed to create PNG for \(path)")
        return
    }
    
    do {
        try pngData.write(to: URL(fileURLWithPath: path))
        print("Created: \(path)")
    } catch {
        print("Error writing \(path): \(error)")
    }
}

// Icon sizes needed for macOS
let sizes = [16, 32, 64, 128, 256, 512, 1024]
let outputDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."

for size in sizes {
    let image = generateAppIcon(size: size)
    let filename = "\(outputDir)/icon_\(size)x\(size).png"
    savePNG(image, to: filename)
    
    // Also create @2x versions
    if size <= 512 {
        let image2x = generateAppIcon(size: size * 2)
        let filename2x = "\(outputDir)/icon_\(size)x\(size)@2x.png"
        savePNG(image2x, to: filename2x)
    }
}

print("Done generating icons!")
