import AppKit
import SwiftUI

/// Render the same vector silhouette used by the app, without an ICNS conversion.
@main struct GenerateMobileIcon {
 @MainActor static func main() throws {
  let root=URL(fileURLWithPath:CommandLine.arguments[1])
  let ctx=CGContext(data:nil,width:1024,height:1024,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.noneSkipLast.rawValue)!
  ctx.setFillColor(CGColor(red:0.975,green:0.973,blue:0.95,alpha:1))
  ctx.fill(CGRect(x:0,y:0,width:1024,height:1024))
  ctx.translateBy(x:12,y:912);ctx.scaleBy(x:5,y:-5)
  let ink=CGColor(red:0.16,green:0.17,blue:0.15,alpha:1)
  let cream=CGColor(red:1,green:0.996,blue:0.96,alpha:1)
  ctx.setFillColor(ink)
  let rect=CGRect(x:0,y:0,width:200,height:160)
  ctx.addPath(DustArms().path(in:rect).cgPath);ctx.fillPath()
  ctx.addPath(DustBody().path(in:rect).cgPath);ctx.fillPath()
  for (x,y) in [(78.0,76.0),(118.0,75.0)] {
   ctx.setFillColor(cream);ctx.fillEllipse(in:CGRect(x:x-9,y:y-12,width:18,height:24))
   ctx.setFillColor(ink);ctx.fillEllipse(in:CGRect(x:x-1.4,y:y-3,width:6.8,height:10))
  }
  ctx.setStrokeColor(cream);ctx.setLineWidth(2.8);ctx.setLineCap(.round)
  ctx.move(to:CGPoint(x:91,y:102));ctx.addQuadCurve(to:CGPoint(x:106,y:102),control:CGPoint(x:98,y:109));ctx.strokePath()
  let bitmap=NSBitmapImageRep(cgImage:ctx.makeImage()!)
  try bitmap.representation(using:.png,properties:[:])!.write(to:root.appendingPathComponent("Mobile/MoteMobile/Assets.xcassets/AppIcon.appiconset/icon.png"))
 }
}
