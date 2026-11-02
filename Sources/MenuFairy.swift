import AppKit

/// Small template frames, cached per state; no display link or idle redraw loop.
@MainActor final class MenuFairy {
    weak var button:NSStatusBarButton?
    private var timer:Timer?
    private var screensSleeping=false
    private var state="idle"
    private var frame=0
    private var frames=[String:[NSImage]]()
    init(button:NSStatusBarButton?){self.button=button
        NSWorkspace.shared.notificationCenter.addObserver(self,selector:#selector(accessibilityChanged),name:NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,object:nil)
        NSWorkspace.shared.notificationCenter.addObserver(self,selector:#selector(sleeping),name:NSWorkspace.screensDidSleepNotification,object:nil)
        NSWorkspace.shared.notificationCenter.addObserver(self,selector:#selector(waking),name:NSWorkspace.screensDidWakeNotification,object:nil)
    }
    func update(_ next:String){guard state != next || button?.image == nil else{return};state=next;restart()}
    @objc private func accessibilityChanged(){restart()}
    @objc private func sleeping(){screensSleeping=true;timer?.invalidate();timer=nil}
    @objc private func waking(){screensSleeping=false;restart()}
    private func restart(){
        timer?.invalidate();timer=nil;frame=0;draw()
        guard !screensSleeping,state != "idle",!NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else{return}
        let timer=Timer(timeInterval:state == "inProgress" ? 0.16:0.32,repeats:true){[weak self] _ in Task{@MainActor in guard let self else{return};self.frame=(self.frame+1)%4;self.draw()}}
        timer.tolerance=0.03;RunLoop.main.add(timer,forMode:.common);self.timer=timer
    }
    private func draw(){
        if frames[state]==nil{frames[state]=(0..<4).map{Self.image(state:state,frame:$0)}}
        button?.image=frames[state]?[frame]
        button?.toolTip=["inProgress":"모트 · 작업 중","approval":"모트 · 승인 대기","answer":"모트 · 답변 대기","unread":"모트 · 미확인 답변이 있어요","failed":"모트 · 오류 확인이 필요해요","idle":"모트 · 쉬는 중"][state]
        button?.setAccessibilityLabel(button?.toolTip ?? "모트")
    }
    private static var portraitAssets=[String:NSImage]()
    static func portrait(state:String,frame:Int)->NSImage {
        let name=state=="idle" ? "mote-dust-sleep-\(frame)":"mote-dust-soft"
        if portraitAssets[name]==nil,let url=Bundle.main.url(forResource:name,withExtension:"svg"),let asset=NSImage(contentsOf:url){portraitAssets[name]=asset}
        guard let asset=portraitAssets[name] else{return image(state:state,frame:frame)}
        return NSImage(size:NSSize(width:200,height:160),flipped:false){_ in
            let bob:CGFloat=state=="inProgress" ? [0,2,0,-2][frame]:0
            asset.draw(in:NSRect(x:0,y:bob,width:200,height:160))
            if let label=["approval":"!","answer":"?","unread":"✉","failed":"!"][state] {
                (label as NSString).draw(at:NSPoint(x:163,y:74+CGFloat(frame%2)*3),withAttributes:[.font:NSFont.systemFont(ofSize:30,weight:.bold),.foregroundColor:NSColor.labelColor])
            }
            return true
        }
    }
    static func image(state:String,frame:Int)->NSImage {
        let image=NSImage(size:NSSize(width:28,height:22),flipped:false){_ in
            let waiting=["approval","answer"].contains(state)
            let unread=state == "unread"
            let working=state == "inProgress"
            let bob:CGFloat=working ? [0,1,0,-1][frame]:0
            let center=NSPoint(x:13+(state=="failed" ? [0,1,0,-1][frame]:0),y:11+bob)
            NSColor.black.setFill()
            let body=NSBezierPath(ovalIn:NSRect(x:center.x-7,y:center.y-6,width:14,height:12))
            for i in 0..<11{let a=Double(i)*2*Double.pi/11;body.appendOval(in:NSRect(x:center.x+cos(a)*6-1.7,y:center.y+sin(a)*5-1.7,width:3.4,height:3.4))}
            body.fill()
            func stroke(_ a:NSPoint,_ b:NSPoint){let p=NSBezierPath();p.lineWidth=1.8;p.lineCapStyle = .round;p.move(to:a);p.line(to:b);p.stroke()}
            NSColor.black.setStroke()
            if working {
                let tap:CGFloat=frame%2==0 ? 2:-1
                stroke(NSPoint(x:6,y:9+bob),NSPoint(x:3,y:5+tap))
                stroke(NSPoint(x:20,y:9+bob),NSPoint(x:24,y:6-tap))
                NSBezierPath(roundedRect:NSRect(x:3,y:2,width:22,height:1.4),xRadius:0.7,yRadius:0.7).fill()
            }else if state=="failed"{
                NSBezierPath(rect:NSRect(x:24,y:10,width:2,height:7)).fill()
                NSBezierPath(ovalIn:NSRect(x:24,y:6,width:2,height:2)).fill()
            }else if unread{
                // Envelope silhouette and a gentle bounce distinguish a delivered reply from an approval.
                let lift:CGFloat=[0,1,2,1][frame]
                NSBezierPath(roundedRect:NSRect(x:18,y:2+lift,width:9,height:6),xRadius:1,yRadius:1).fill()
                NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current?.compositingOperation = .clear
                stroke(NSPoint(x:19,y:7+lift),NSPoint(x:22.5,y:4.5+lift));stroke(NSPoint(x:22.5,y:4.5+lift),NSPoint(x:26,y:7+lift))
                NSGraphicsContext.restoreGraphicsState()
            }else if waiting{
                // A question bubble and approval hand stay distinct even with motion disabled.
                if state == "answer" {
                    NSBezierPath(roundedRect:NSRect(x:0,y:14,width:7,height:6),xRadius:2,yRadius:2).fill()
                    let tail=NSBezierPath();tail.move(to:NSPoint(x:4,y:14));tail.line(to:NSPoint(x:6,y:12));tail.line(to:NSPoint(x:6,y:15));tail.close();tail.fill()
                }
                if state == "approval" {
                    // A tall isolated badge is distinct from the question bubble at 1x size.
                    NSBezierPath(roundedRect:NSRect(x:23,y:9,width:4,height:11),xRadius:1,yRadius:1).fill()
                    NSBezierPath(ovalIn:NSRect(x:23.5,y:5,width:3,height:3)).fill()
                }else{
                    let wave:CGFloat=[0,3,1,-1][frame]
                    stroke(NSPoint(x:19,y:12),NSPoint(x:24+wave/2,y:18+wave/2))
                }
            }
            // Transparent eye cutouts make template images legible in either menu-bar appearance.
            NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current?.compositingOperation = .clear
            for x in [9.0,15.0] {NSBezierPath(ovalIn:NSRect(x:x,y:center.y-0.5,width:waiting ? 3.3:2.6,height:state == "idle" ? 1.4:4)).fill()}
            if state == "idle" {NSBezierPath(ovalIn:NSRect(x:11.5,y:6,width:2.5,height:3)).fill()}
            else {let smile=NSBezierPath();smile.lineWidth=0.9;smile.move(to:NSPoint(x:11,y:7+bob));smile.curve(to:NSPoint(x:15,y:7+bob),controlPoint1:NSPoint(x:12,y:5+bob),controlPoint2:NSPoint(x:14,y:5+bob));smile.stroke()}
            NSGraphicsContext.restoreGraphicsState()
            if state != "idle" {NSColor.black.setFill();for x:CGFloat in [10.3,16.3]{NSBezierPath(ovalIn:NSRect(x:x,y:center.y+0.4,width:1,height:1.8)).fill()}}
            return true
        };image.isTemplate=true;return image
    }
}
