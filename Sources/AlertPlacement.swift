import Foundation
import CoreGraphics

struct AlertPlacement {
    static func frame(in visible:NSRect,safeTop:CGFloat,width:CGFloat=350,height:CGFloat=110)->NSRect {
        let w=min(width,max(100,visible.width-24)),h=min(height,max(60,visible.height-24))
        let top=min(visible.maxY,safeTop)-14
        return NSRect(x:visible.maxX-w-14,y:max(visible.minY+12,top-h),width:w,height:h)
    }
}
