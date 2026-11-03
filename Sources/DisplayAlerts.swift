import AppKit
import SwiftUI

@MainActor final class DisplayAlerts {
    private let presentsWindows:Bool
    init(presentsWindows:Bool=true){self.presentsWindows=presentsWindows}
    var displayedIdentifier:String? {current?.id}
    private var panel:NSPanel?
    var onSnooze:((Set<String>)->Void)?
    private var hideTask:Task<Void,Never>?
    private struct Notice {
        let id:String;let title:String;let body:String;let threads:Set<String>;let open:()->Void;let priority:Int;let sound:Bool;let queued:Date
    }
    private var pending=[Notice]()
    private var current:Notice?
    private var token=UUID()
    private var mode="cursor"
    func show(title:String,body:String,mode:String,sound:Bool,threads:Set<String>=[],identifier:String=UUID().uuidString,priority:Int=0,open:@escaping()->Void){
        self.mode=mode
        guard current?.id != identifier else{return}
        pending.removeAll{$0.id==identifier}
        pending.append(Notice(id:identifier,title:title,body:body,threads:threads,open:open,priority:priority,sound:sound,queued:Date()))
        if pending.count>20{pending.remove(at:pending.firstIndex(where:{$0.priority==0}) ?? 0)}
        if current==nil || priority>(current?.priority ?? -1){next()}
    }
    func hideAll(){pending=[];hideTask?.cancel();panel?.orderOut(nil);current=nil;token=UUID()}
    func cancel(identifiers:Set<String>){
        pending.removeAll{identifiers.contains($0.id)}
        if let current,identifiers.contains(current.id){next()}
    }
    func cancel(threads:Set<String>){
        pending.removeAll{PresentationPolicy.resolvedGroup($0.threads,by:threads)}
        if let current,PresentationPolicy.resolvedGroup(current.threads,by:threads){next()}
    }
    func snoozeCurrent(){
        guard let current,!current.threads.isEmpty else{return}
        let expected=token;onSnooze?(current.threads);advance(expected)
    }
    private func advance(_ expected:UUID){guard token==expected else{return};next()}
    private func next(){
        hideTask?.cancel();panel?.orderOut(nil);current=nil;token=UUID()
        pending.removeAll{Date().timeIntervalSince($0.queued)>30}
        guard let index=pending.indices.max(by:{pending[$0].priority<pending[$1].priority}) else{return}
        // Equal priorities retain FIFO ordering, even after a completion is preempted.
        let priority=pending[index].priority
        let alert=pending.remove(at:pending.firstIndex(where:{$0.priority==priority})!);current=alert
        let expected=token
        guard presentsWindows else{return}
        let point=NSEvent.mouseLocation
        let fixed=mode.hasPrefix("display:") ? NSScreen.screens.first{screen in
            let id=(screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.stringValue
            return "display:"+(id ?? "")==mode
        }:nil
        guard let screen=fixed ?? (mode=="main" ? NSScreen.screens.first:NSScreen.screens.first(where:{$0.frame.contains(point)})) ?? NSScreen.main else{return}
        let frame=AlertPlacement.frame(in:screen.visibleFrame,safeTop:screen.frame.maxY-screen.safeAreaInsets.top)
        let p=NSPanel(contentRect:frame,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        p.isOpaque=false;p.backgroundColor = .clear;p.hasShadow=true;p.level = .statusBar
        p.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary,.ignoresCycle];p.hidesOnDeactivate=false;p.isReleasedWhenClosed=false
        let view=DisplayAlertView(title:alert.title,message:alert.body,open:{[weak self] in alert.open();self?.advance(expected)},close:{[weak self] in self?.advance(expected)},snooze:alert.threads.isEmpty ? nil:{[weak self] in self?.snoozeCurrent()})
        p.contentView=NSHostingView(rootView:view.frame(width:frame.width,height:frame.height).background(Glass()).clipShape(RoundedRectangle(cornerRadius:17)))
        panel=p;p.orderFrontRegardless()
        if alert.sound{NSSound(named:"Glass")?.play()}
        hideTask=Task{[weak self] in do{try await Task.sleep(nanoseconds:10_000_000_000)}catch{return};self?.advance(expected)}
    }

}
struct DisplayAlertView:View {
    var title:String;var message:String;var open:()->Void;var close:()->Void;var snooze:(()->Void)? = nil
    var bodyView:some View {
        HStack(alignment:.center,spacing:9){
            Image(systemName:title.localizedCaseInsensitiveContains(L10n.text("승인")) ? "hand.raised":title.localizedCaseInsensitiveContains(L10n.text("답변")) || title.localizedCaseInsensitiveContains(L10n.text("응답")) ? "message":title.localizedCaseInsensitiveContains(L10n.text("네트워크")) ? "wifi.slash":"envelope").font(.system(size:18)).foregroundStyle(title.localizedCaseInsensitiveContains(L10n.text("승인")) || title.localizedCaseInsensitiveContains(L10n.text("네트워크")) ? Color.orange:title.localizedCaseInsensitiveContains(L10n.text("답변")) || title.localizedCaseInsensitiveContains(L10n.text("응답")) ? Color(nsColor:.systemTeal):Palette.olive).frame(width:24,height:22).accessibilityHidden(true)
            Button(action:open){VStack(alignment:.leading,spacing:4){Text(title).font(.system(size:13,weight:.semibold));Text(message.replacingOccurrences(of:"\n",with:" · ")).font(.system(size:12)).lineLimit(1).multilineTextAlignment(.leading)}.frame(maxWidth:.infinity,alignment:.leading)}.buttonStyle(.plain)
            if let snooze{Button(action:snooze){Image(systemName:"clock.arrow.circlepath").font(.system(size:12))}.buttonStyle(.plain).help(L10n.text("10분 뒤 다시 알림")).accessibilityLabel(L10n.text("10분 뒤 다시 알림"))}
            Button(L10n.text("열기"),action:open).font(.system(size:11,weight:.semibold)).buttonStyle(.plain).help(L10n.text("해당 대화 열기 · 승인이나 답변을 대신 보내지 않아요"))
            Button(action:close){Image(systemName:"xmark").font(.system(size:11)).frame(width:24,height:24)}.buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel(L10n.text("알림 닫기"))
        }.padding(12)
    }
    var body:some View {bodyView}
}
