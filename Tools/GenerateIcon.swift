import AppKit

@main struct GenerateIcon {
    @MainActor static func main() throws {
        let directory=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        for size in [16,32,64,128,256,512,1024]{
            let image=NSImage(size:NSSize(width:size,height:size));image.lockFocus()
            let ctx=NSGraphicsContext.current!.cgContext;ctx.scaleBy(x:CGFloat(size)/1024,y:CGFloat(size)/1024)
            NSColor(calibratedRed:0.89,green:0.88,blue:0.82,alpha:1).setFill()
            NSBezierPath(roundedRect:NSRect(x:15,y:15,width:994,height:994),xRadius:223,yRadius:223).fill()
            NSColor(calibratedRed:0.30,green:0.34,blue:0.25,alpha:1).setFill()
            NSBezierPath(roundedRect:NSRect(x:60,y:60,width:904,height:904),xRadius:185,yRadius:185).fill()
            NSColor(calibratedRed:0.15,green:0.17,blue:0.13,alpha:1).setFill()
            let body=NSBezierPath(ovalIn:NSRect(x:220,y:245,width:580,height:530))
            for i in 0..<20 {let a=Double(i)*Double.pi/10;body.appendOval(in:NSRect(x:470+cos(a)*270,y:470+sin(a)*245,width:80,height:80))};body.fill()
            NSColor(calibratedRed:0.96,green:0.95,blue:0.89,alpha:1).setFill()
            for x in [365.0,555.0]{NSBezierPath(ovalIn:NSRect(x:x,y:490,width:85,height:115)).fill()}
            NSColor(calibratedRed:0.15,green:0.17,blue:0.13,alpha:1).setFill()
            for x in [405.0,595.0]{NSBezierPath(ovalIn:NSRect(x:x,y:535,width:25,height:40)).fill()}
            NSColor(calibratedRed:0.96,green:0.95,blue:0.89,alpha:1).setStroke();let mouth=NSBezierPath();mouth.lineWidth=14;mouth.lineCapStyle = .round;mouth.move(to:NSPoint(x:480,y:420));mouth.curve(to:NSPoint(x:545,y:420),controlPoint1:NSPoint(x:495,y:400),controlPoint2:NSPoint(x:530,y:400));mouth.stroke()
            image.unlockFocus()
            var rect=NSRect(origin:.zero,size:image.size)
            let bitmap=NSBitmapImageRep(cgImage:image.cgImage(forProposedRect:&rect,context:nil,hints:nil)!)
            let data=bitmap.representation(using:.png,properties:[:])!
            let labels:[Int:[String]]=[16:["icon_16x16.png"],32:["icon_16x16@2x.png","icon_32x32.png"],64:["icon_32x32@2x.png"],128:["icon_128x128.png"],256:["icon_128x128@2x.png","icon_256x256.png"],512:["icon_256x256@2x.png","icon_512x512.png"],1024:["icon_512x512@2x.png"]]
            // lockFocus uses backing pixels; resize to the requested bitmap dimensions explicitly.
            let output=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:size,pixelsHigh:size,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
            NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:output)
            image.draw(in:NSRect(x:0,y:0,width:size,height:size),from:.zero,operation:.copy,fraction:1)
            NSGraphicsContext.restoreGraphicsState()
            let pixels=output.representation(using:.png,properties:[:]) ?? data
            for label in labels[size] ?? []{try pixels.write(to:directory.appendingPathComponent(label))}
        }
    }
}
