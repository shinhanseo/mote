import AppKit
import SwiftUI

@MainActor final class DisplayAlerts {
    private var panel:NSPanel?
    private var hideTask:Task<Void,Never>?
    private var pending:[(title:String,body:String,open:()->Void)]=[]
    private var mode="cursor"
    func show(title:String,body:String,mode:String,sound:Bool,open:@escaping()->Void){
        self.mode=mode
        pending.append((title,body,open))
        if pending.count>20{pending.removeFirst(pending.count-20)}
        if sound{NSSound(named:"Glass")?.play()}
        if panel?.isVisible != true{next()}
    }
    private func next(){
        hideTask?.cancel()
        panel?.orderOut(nil)
        guard !pending.isEmpty else{return}
        let alert=pending.removeFirst()
        let point=NSEvent.mouseLocation
        guard let screen=(mode=="main" ? NSScreen.screens.first:NSScreen.screens.first(where:{$0.frame.contains(point)})) ?? NSScreen.main else{return}
        let frame=AlertPlacement.frame(in:screen.visibleFrame,safeTop:screen.frame.maxY-screen.safeAreaInsets.top)
        let p=NSPanel(contentRect:frame,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        p.isOpaque=false;p.backgroundColor = .clear;p.hasShadow=true;p.level = .statusBar
        p.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary,.ignoresCycle];p.hidesOnDeactivate=false;p.isReleasedWhenClosed=false
        let view=DisplayAlertView(title:alert.title,message:alert.body,open:{[weak self] in alert.open();self?.next()},close:{[weak self] in self?.next()})
        p.contentView=NSHostingView(rootView:view.frame(width:frame.width,height:frame.height).background(Glass()).clipShape(RoundedRectangle(cornerRadius:17)))
        panel=p;p.orderFrontRegardless() // Never activate Mote or steal typing focus.
        hideTask=Task{[weak self] in try? await Task.sleep(nanoseconds:10_000_000_000);guard !Task.isCancelled else{return};self?.next()}
    }
}
struct DisplayAlertView:View {
    var title:String;var message:String;var open:()->Void;var close:()->Void
    var bodyView:some View {
        HStack(alignment:.top,spacing:12){
            Image(nsImage:MenuFairy.image(state:"unread",frame:0)).resizable().scaledToFit().frame(width:30,height:26).accessibilityHidden(true)
            Button(action:open){VStack(alignment:.leading,spacing:6){Text(title).font(.system(size:13,weight:.semibold));Text(message).font(.system(size:13)).lineLimit(2).multilineTextAlignment(.leading)}.frame(maxWidth:.infinity,alignment:.leading)}.buttonStyle(.plain)
            Button(action:close){Image(systemName:"xmark").font(.system(size:11)).frame(width:24,height:24)}.buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("알림 닫기")
        }.padding(17)
    }
    var body:some View {bodyView}
}
