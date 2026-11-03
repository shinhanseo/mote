import AppKit
let root=URL(fileURLWithPath:CommandLine.arguments[1])
let source=NSImage(contentsOf:root.appendingPathComponent("Resources/Mote.icns"))!
let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:1024,pixelsHigh:1024,bitsPerSample:8,samplesPerPixel:3,hasAlpha:false,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:bitmap)
NSColor(calibratedRed:0.975,green:0.973,blue:0.95,alpha:1).setFill()
NSBezierPath(rect:NSRect(x:0,y:0,width:1024,height:1024)).fill()
source.draw(in:NSRect(x:0,y:0,width:1024,height:1024))
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using:.png,properties:[:])!.write(to:root.appendingPathComponent("Mobile/MoteMobile/Assets.xcassets/AppIcon.appiconset/icon.png"))
