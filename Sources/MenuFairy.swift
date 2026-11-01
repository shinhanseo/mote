import AppKit

/// Small template frames, cached per state; no display link or idle redraw loop.
@MainActor final class MenuFairy {
    weak var button:NSStatusBarButton?
    private var timer:Timer?
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
    @objc private func sleeping(){timer?.invalidate();timer=nil}
    @objc private func waking(){restart()}
    private func restart(){
        timer?.invalidate();timer=nil;frame=0;draw()
        guard state != "idle",!NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else{return}
        let timer=Timer(timeInterval:state == "inProgress" ? 0.18:0.28,repeats:true){[weak self] _ in Task{@MainActor in guard let self else{return};self.frame=(self.frame+1)%4;self.draw()}}
        timer.tolerance=0.03;RunLoop.main.add(timer,forMode:.common);self.timer=timer
    }
    private func draw(){
        if frames[state]==nil{frames[state]=(0..<4).map{Self.image(state:state,frame:$0)}}
        button?.image=frames[state]?[frame]
        button?.toolTip=["inProgress":"모트 · 작업 중","approval":"모트 · 승인 대기","answer":"모트 · 답변 대기","idle":"모트 · 쉬는 중"][state]
        button?.setAccessibilityLabel(button?.toolTip ?? "모트")
    }
    static func image(state:String,frame:Int)->NSImage {
        let image=NSImage(size:NSSize(width:28,height:22),flipped:false){_ in
            let waiting=["approval","answer"].contains(state)
            let working=state == "inProgress"
            let bob:CGFloat=working ? [0,1,0,-1][frame]:0
            let center=NSPoint(x:13,y:11+bob)
            NSColor.black.setFill()
            let body=NSBezierPath(ovalIn:NSRect(x:center.x-7,y:center.y-6,width:14,height:12))
            for i in 0..<12{let a=Double(i)*Double.pi/6;body.appendOval(in:NSRect(x:center.x+cos(a)*6-1.7,y:center.y+sin(a)*5-1.7,width:3.4,height:3.4))}
            body.fill()
            func stroke(_ a:NSPoint,_ b:NSPoint){let p=NSBezierPath();p.lineWidth=1.8;p.lineCapStyle = .round;p.move(to:a);p.line(to:b);p.stroke()}
            NSColor.black.setStroke()
            if working {
                let tap:CGFloat=frame%2==0 ? 2:-1
                stroke(NSPoint(x:6,y:9+bob),NSPoint(x:3,y:5+tap))
                stroke(NSPoint(x:20,y:9+bob),NSPoint(x:24,y:6-tap))
                NSBezierPath(roundedRect:NSRect(x:3,y:2,width:22,height:1.4),xRadius:0.7,yRadius:0.7).fill()
            }else if waiting{
                let wave:CGFloat=[0,3,1,-1][frame]
                stroke(NSPoint(x:19,y:12),NSPoint(x:24+wave/2,y:18+wave/2))
                NSBezierPath(ovalIn:NSRect(x:23+wave/2,y:17+wave/2,width:3,height:3)).fill()
                if state == "approval" {NSBezierPath(rect:NSRect(x:2,y:16,width:1.5,height:4)).fill();NSBezierPath(ovalIn:NSRect(x:2,y:13,width:1.5,height:1.5)).fill()}
            }
            // Transparent eye cutouts make template images legible in either menu-bar appearance.
            NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current?.compositingOperation = .clear
            for x in [9.0,15.0] {NSBezierPath(ovalIn:NSRect(x:x,y:center.y-0.5,width:waiting ? 3.3:2.6,height:state == "idle" ? 1.4:4)).fill()}
            NSGraphicsContext.restoreGraphicsState()
            return true
        };image.isTemplate=true;return image
    }
}
