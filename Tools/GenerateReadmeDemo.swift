// Reproducible illustrative animation using Mote's existing vector mascot.
import AppKit
import ImageIO
import UniformTypeIdentifiers
let width=900, height=430
let en=CommandLine.arguments.contains("--english")
let output=en ? "docs/assets/mote-demo-en.gif":"docs/assets/mote-demo.gif"
let mascot=NSImage(contentsOfFile:"website/assets/mote-dust-soft.svg")!
func color(_ hex:UInt32)->NSColor{NSColor(srgbRed:Double((hex>>16)&255)/255,green:Double((hex>>8)&255)/255,blue:Double(hex&255)/255,alpha:1)}
let ink=color(0x292b27), muted=color(0x7c8175), olive=color(0x687454), teal=color(0x285e65)
func box(_ x:Double,_ y:Double,_ w:Double,_ h:Double,_ fill:NSColor,_ radius:Double=12){fill.setFill();NSBezierPath(roundedRect:NSRect(x:x,y:Double(height)-y-h,width:w,height:h),xRadius:radius,yRadius:radius).fill()}
func text(_ value:String,_ x:Double,_ y:Double,_ size:Double,_ c:NSColor,_ weight:NSFont.Weight = .regular){let attrs:[NSAttributedString.Key:Any]=[.font:NSFont.systemFont(ofSize:size,weight:weight),.foregroundColor:c];let s=value as NSString;let h=s.size(withAttributes:attrs).height;s.draw(at:NSPoint(x:x,y:Double(height)-y-h),withAttributes:attrs)}
let destination=CGImageDestinationCreateWithURL(URL(fileURLWithPath:output) as CFURL,UTType.gif.identifier as CFString,90,nil)!
CGImageDestinationSetProperties(destination,[kCGImagePropertyGIFDictionary:[kCGImagePropertyGIFLoopCount:0]] as CFDictionary)
for frame in 0..<90 {autoreleasepool{
 let stage=frame/30, t=Double(frame%30)/30
 let rep=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:width,pixelsHigh:height,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
 NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:rep)
 box(0,0,900,430,color(0xe9ece2),20)
 box(0,0,900,32,color(0xf2f3ec),0)
 text("●  Finder",22,9,11,muted,.medium)
 text(stage==0 ? (en ? "Working 1":"진행 1"):stage==1 ? (en ? "Input 1":"입력 대기 1"):(en ? "Unread 1":"답변 1"),745,9,11,ink,.medium)
 // Background editor, deliberately synthetic and without private data.
 box(38,70,365,238,color(0xf6f7f0),14)
 for i in 0..<3{box(55+Double(i)*13,84,6,6,color(0xd4d8cc),3)}
 text(en ? "Your other work":"그동안, 하던 일을.",60,116,22,ink,.semibold)
 text(en ? "Mote will let you know when you are needed.":"필요한 순간엔 모트가 불러줄게요.",60,153,12,muted)
 for i in 0..<4{box(60,194+Double(i)*19,Double([245,190,266,150][i]),5,color(0xe2e6d9),2)}
 // Compact app panel.
 box(425,63,425,315,color(0xdde2d3),18)
 box(421,59,425,315,color(0xfafbf5),18)
 text("mote.",445,78,22,ink,.bold);text(en ? "● Connected":"● 연결됨",516,88,10,olive)
 text(en ? "A little dust, looking out for you.":"작은 먼지가 챙겨둘게요",445,126,10,muted)
 let headline=en ? ["One task is working.","Codex needs your reply.","A reply is ready."][stage]:["1개 작업이 진행 중이에요.","답변을 기다려요.","답변이 도착했어요."][stage]
 text(headline,445,148,en ? 22:25,ink,.semibold)
 let bounce=stage==0 ? sin(t*Double.pi*8)*2:sin(t*Double.pi*2)*3
 mascot.draw(in:NSRect(x:735,y:Double(height)-117-77+bounce,width:96,height:77))
 if stage==1{text("?",821,130,24,teal,.bold)}
 if stage==2{text("✉",815,161,18,olive,.semibold)}
 text(en ? "Pinned chat":"고정한 대화",445,204,10,muted,.medium)
 box(442,226,382,72,color(stage==1 ? 0xe7eeea:0xf0f2ea),11)
 let icon=stage==0 ? "◌":stage==1 ? "?":"✉"
 text(icon,459,247,23,stage==1 ? teal:olive,.semibold)
 text(en ? "Implement login screen":"로그인 화면 구현",497,240,14,ink,.medium)
 text(en ? ["web-app · Working","web-app · Your input is needed","web-app · Reply ready · Unread"][stage]:["web-app · 작업 중","web-app · 진행 방식을 선택해 주세요","web-app · 답변 도착 · 미확인"][stage],497,263,11,stage==1 ? teal:muted)
 text(en ? "Open ↗":"열기 ↗",772,248,11,olive,.medium)
 text(en ? "Notifications on":"알림 켜짐",445,333,10,muted)
 text("···",799,325,20,olive)
 if stage>0 {
 let appear=min(1,t*6),dy=(1-appear)*12
 box(51,324+dy,330,66,color(0xd4daca).withAlphaComponent(appear),12)
 box(47,320+dy,330,66,color(0xfffefa).withAlphaComponent(appear),12)
 text(stage==1 ? "?":"✉",65,337+dy,22,stage==1 ? teal:olive,.semibold)
 text(en ? (stage==1 ? "Mote · Your reply is needed":"Mote · A reply is ready"):(stage==1 ? "모트 · 답변을 기다려요":"모트 · 답변이 도착했어요"),102,332+dy,13,ink,.semibold)
 text(en ? "Implement login screen":"로그인 화면 구현",102,354+dy,11,muted)
 text("↗",345,343+dy,14,olive)
 }
 let labels=en ? ["01  Keep working","02  Catch the moment","03  Go straight back"]:["01  하던 일에 집중하고","02  필요한 순간을 알고","03  그 대화로 돌아가요"]
 for i in 0..<3{box(240+Double(i)*143,405,125,3,i==stage ? olive:color(0xd0d6c7),1.5)}
 text(labels[stage],38,402,11,olive,.medium)
 NSGraphicsContext.restoreGraphicsState()
 CGImageDestinationAddImage(destination,rep.cgImage!,[kCGImagePropertyGIFDictionary:[kCGImagePropertyGIFDelayTime:0.1,kCGImagePropertyGIFUnclampedDelayTime:0.1]] as CFDictionary)
}}
assert(CGImageDestinationFinalize(destination));print("Generated \(output)")
