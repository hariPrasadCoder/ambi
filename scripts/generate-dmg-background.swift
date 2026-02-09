#!/usr/bin/env swift

import Cocoa

// Generate DMG background with "drag to Applications" design
func generateDMGBackground() -> NSImage {
    let width = 660
    let height = 400
    let image = NSImage(size: NSSize(width: width, height: height))
    
    image.lockFocus()
    
    let rect = NSRect(x: 0, y: 0, width: width, height: height)
    
    // Background gradient
    let gradient = NSGradient(colors: [
        NSColor(red: 0.12, green: 0.12, blue: 0.15, alpha: 1.0),  // Dark
        NSColor(red: 0.08, green: 0.08, blue: 0.12, alpha: 1.0)   // Darker
    ])!
    gradient.draw(in: rect, angle: -90)
    
    // Title "Ambi"
    let titleFont = NSFont.systemFont(ofSize: 42, weight: .bold)
    let titleAttributes: [NSAttributedString.Key: Any] = [
        .font: titleFont,
        .foregroundColor: NSColor.white
    ]
    let title = "Ambi"
    let titleSize = title.size(withAttributes: titleAttributes)
    let titlePoint = NSPoint(x: (CGFloat(width) - titleSize.width) / 2, y: CGFloat(height) - 70)
    title.draw(at: titlePoint, withAttributes: titleAttributes)
    
    // Subtitle
    let subtitleFont = NSFont.systemFont(ofSize: 14, weight: .regular)
    let subtitleAttributes: [NSAttributedString.Key: Any] = [
        .font: subtitleFont,
        .foregroundColor: NSColor(white: 0.7, alpha: 1.0)
    ]
    let subtitle = "Ambient Voice Recorder"
    let subtitleSize = subtitle.size(withAttributes: subtitleAttributes)
    let subtitlePoint = NSPoint(x: (CGFloat(width) - subtitleSize.width) / 2, y: CGFloat(height) - 95)
    subtitle.draw(at: subtitlePoint, withAttributes: subtitleAttributes)
    
    // Draw arrow
    let arrowColor = NSColor(red: 0.5, green: 0.55, blue: 1.0, alpha: 0.8)
    arrowColor.setStroke()
    arrowColor.setFill()
    
    let arrowPath = NSBezierPath()
    arrowPath.lineWidth = 3
    
    // Arrow line (from app icon area to Applications area)
    let arrowStartX: CGFloat = 220
    let arrowEndX: CGFloat = 440
    let arrowY: CGFloat = 180
    
    arrowPath.move(to: NSPoint(x: arrowStartX, y: arrowY))
    arrowPath.line(to: NSPoint(x: arrowEndX - 15, y: arrowY))
    arrowPath.stroke()
    
    // Arrow head
    let arrowHead = NSBezierPath()
    arrowHead.move(to: NSPoint(x: arrowEndX, y: arrowY))
    arrowHead.line(to: NSPoint(x: arrowEndX - 20, y: arrowY + 12))
    arrowHead.line(to: NSPoint(x: arrowEndX - 20, y: arrowY - 12))
    arrowHead.close()
    arrowHead.fill()
    
    // Instructions text
    let instructionFont = NSFont.systemFont(ofSize: 13, weight: .medium)
    let instructionAttributes: [NSAttributedString.Key: Any] = [
        .font: instructionFont,
        .foregroundColor: NSColor(white: 0.6, alpha: 1.0)
    ]
    let instruction = "Drag to Applications to install"
    let instructionSize = instruction.size(withAttributes: instructionAttributes)
    let instructionPoint = NSPoint(x: (CGFloat(width) - instructionSize.width) / 2, y: 60)
    instruction.draw(at: instructionPoint, withAttributes: instructionAttributes)
    
    image.unlockFocus()
    return image
}

func savePNG(_ image: NSImage, to path: String) {
    guard let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData),
          let pngData = bitmap.representation(using: .png, properties: [:]) else {
        print("Failed to create PNG")
        return
    }
    
    do {
        try pngData.write(to: URL(fileURLWithPath: path))
        print("Created: \(path)")
    } catch {
        print("Error: \(error)")
    }
}

let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "dmg-background.png"
let image = generateDMGBackground()
savePNG(image, to: outputPath)
