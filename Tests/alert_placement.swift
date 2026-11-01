import Foundation
import CoreGraphics
for visible in [NSRect(x:0,y:0,width:1512,height:940),NSRect(x:-2560,y:0,width:2560,height:1410),NSRect(x:0,y:1000,width:1920,height:1060)] {
    let frame=AlertPlacement.frame(in:visible,safeTop:visible.maxY-24)
    precondition(visible.contains(frame),"Alert must fit monitor coordinates including negative origins")
    precondition(frame.maxY<=visible.maxY-24,"Alert must avoid notch/menu bar")
}
print("PASS: internal, left external and vertically arranged monitor placement")
