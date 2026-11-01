import AppKit
import SwiftUI
import UserNotifications
import SQLite3

struct Job: Identifiable, Equatable {
    var id: String; var title: String; var project: String; var status: String; var turn: String; var readReceipt:Bool? = nil
    var label: String { switch status {case "unread": return "답변 도착 · 미확인"; case "approval": return "승인 대기"; case "answer": return "답변 대기"; case "inProgress": return "작업 중"; case "completed": return "완료"; case "failed": return "오류"; case "interrupted": return "중단됨"; default: return "확인 필요"} }
    var symbol: String { switch status {case "unread": return "envelope.badge"; case "approval": return "hand.raised"; case "answer": return "message"; case "inProgress": return "ellipsis"; case "completed": return "checkmark"; case "failed": return "exclamationmark.triangle"; default: return "questionmark"} }
}
struct LocalReader {
    static func query(_ path: String, _ sql: String) throws -> [[String]] {
        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else { if let db { sqlite3_close(db) }; throw NSError(domain: "Codex 기록을 열 수 없어요", code: 1) }
        defer { sqlite3_close(db) }; sqlite3_busy_timeout(db, 1000)
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw NSError(domain: "Codex 기록 형식이 변경되었어요", code: 2) }
        defer { sqlite3_finalize(stmt) }; var rows = [[String]]()
        while true { let step = sqlite3_step(stmt); if step == SQLITE_DONE { break }; guard step == SQLITE_ROW else { throw NSError(domain: "Codex 기록 읽기 실패", code: 3) }
            rows.append((0..<sqlite3_column_count(stmt)).map { i in sqlite3_column_text(stmt,i).map { String(cString:$0) } ?? "" })
        }; return rows
    }
    static func read() throws -> [Job] {
        let home = ProcessInfo.processInfo.environment["CODEX_HOME"] ?? NSHomeDirectory()+"/.codex"
        let files = try FileManager.default.contentsOfDirectory(atPath:home)
        guard let state = files.filter({$0.hasPrefix("state_") && $0.hasSuffix(".sqlite")}).sorted(by:{$0.localizedStandardCompare($1) == .orderedDescending}).first else { throw NSError(domain:"Codex 기록을 찾지 못했어요",code:4) }
        let columns=try query(home+"/"+state,"PRAGMA table_info(threads)").map{$0[1]}
        let titleColumn=columns.contains("name") ? "COALESCE(NULLIF(TRIM(name),''),'')" : "''"
        let threads = try query(home+"/"+state,"SELECT id, \(titleColumn), cwd FROM threads WHERE archived=0 AND agent_path IS NULL ORDER BY updated_at DESC LIMIT 20")
        let turns = try query(home+"/thread_history_1.sqlite", "SELECT t.thread_id,t.turn_id,t.status,COALESCE(t.started_at,0) FROM thread_turns t JOIN (SELECT thread_id,MAX(rollout_ordinal) n FROM thread_turns GROUP BY thread_id) latest ON t.thread_id=latest.thread_id AND t.rollout_ordinal=latest.n")
        // Desktop read receipts are authoritative for the published turn. Stream snapshots
        // can retain hasUnreadTurn after the desktop handles a separate read-state event.
        let receiptRows=(try? query(home+"/"+state,"SELECT thread_id, first_unread_turn IS NOT NULL, COALESCE(last_published_turn,'') FROM thread_read_receipts")) ?? []
        let receipts=Dictionary(receiptRows.map{($0[0],$0)},uniquingKeysWith:{_,b in b})
        let lookup = Dictionary(turns.map { ($0[0],$0) }, uniquingKeysWith: { a,b in b })
        return threads.map { row in
            let t = lookup[row[0]]; var status = t?[2] ?? "unknown"
            // In-progress rows can survive a terminated Codex process. Never invent completion.
            if status == "inProgress", let stamp = Double(t?[3] ?? "0") {
                let seconds = stamp > 10_000_000_000 ? stamp/1000 : stamp
                if Date().timeIntervalSince1970-seconds > 6*3600 { status="unknown" }
            }
            return Job(id:row[0],title:row[1].isEmpty ? "제목 없는 대화" : row[1],project:URL(fileURLWithPath:row[2]).lastPathComponent,status:status,turn:t?[1] ?? "",readReceipt:receipts[row[0]].flatMap{ receipt in receipt[2] == t?[1] ? receipt[1] == "1" : nil })
        }
    }
}

@MainActor final class Monitor: ObservableObject {
    @Published var jobs=[Job](); @Published var error: String?; @Published var selected: String?; @Published var all=false
    @Published var notificationStatus="알림 권한 확인 중"; @Published var muted=false
    @Published var liveConnected=false
    let live=LiveObserver();var rawJobs=[Job]();var liveStates=[String:LiveState]();var waitSignatures=[String:String]()
    var waiting:Int {jobs.filter{["approval","answer"].contains($0.status)}.count}
    var unread:Int {jobs.filter{$0.status=="unread"}.count}
    var fairyStatus:String {waiting>0 ? (jobs.first{["approval","answer"].contains($0.status)}?.status ?? "answer") : unread>0 ? "unread" : active>0 ? "inProgress":"idle"}
    var baseline=false; var previous=[String:Job](); var timer: Timer?; var reading=false
    var onUpdate: (() -> Void)?
    var active: Int { jobs.filter{$0.status=="inProgress"}.count }
    var chosen: Job? { jobs.first{$0.id==selected} ?? jobs.first }
    func start() {
        live.onState = {[weak self] id,state in Task { @MainActor in self?.receive(id,state) }}
        live.onConnection = {[weak self] connected in Task { @MainActor in guard let self else{return};self.liveConnected=connected;fputs("Mote IPC connected: \(connected)\n",stderr);if !connected{self.liveStates.removeAll();self.waitSignatures.removeAll();self.reconcile();self.onUpdate?()}}}
        live.start();refresh(); timer=Timer.scheduledTimer(withTimeInterval:3,repeats:true){[weak self] _ in Task { @MainActor in self?.refresh() }}; updatePermission() }
    func updatePermission() { UNUserNotificationCenter.current().getNotificationSettings { settings in Task { @MainActor in self.notificationStatus = settings.authorizationStatus == .authorized ? "알림 켜짐" : "알림 허용 필요" } } }
    func requestNotifications() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            if settings.authorizationStatus == .denied {Task { @MainActor in if let url=URL(string:"x-apple.systempreferences:com.apple.Notifications-Settings.extension"){NSWorkspace.shared.open(url)} }}
            else {UNUserNotificationCenter.current().requestAuthorization(options:[.alert,.sound]) { _,_ in Task { @MainActor in self.updatePermission() } }}
        }
    }
    func notify(_ job:Job) {
        guard !muted else {return}; let content=UNMutableNotificationContent();content.title=["approval":"모트 · 승인이 필요해요","answer":"모트 · 답변을 기다리고 있어요","failed":"모트 · 작업에 문제가 생겼어요"][job.status] ?? "모트 · 작업이 끝났어요";content.body=String(job.title.prefix(100));content.sound = .default; content.userInfo=["threadID":job.id]
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier:job.id+job.turn+job.status,content:content,trigger:nil)) { error in if let error {fputs("Mote notification: \(error.localizedDescription)\n",stderr)} }
    }
    func refresh() {
        guard !reading else{return}; reading=true
        Task.detached { let result = Result { try LocalReader.read() }; await self.apply(result) }
    }
    func apply(_ result:Result<[Job],Error>) {
        reading=false
        switch result {case .success(let found):
            if baseline { for j in found { if let old=previous[j.id], j.turn == old.turn, old.status == "inProgress", ["completed","failed"].contains(j.status) { notify(j) } } }
            previous=Dictionary(uniqueKeysWithValues:found.map{($0.id,$0)});rawJobs=found;live.observe(found.map(\.id));reconcile();error=nil;baseline=true
        case .failure(let e): error=e.localizedDescription }
        onUpdate?()
    }
    func receive(_ id:String,_ state:LiveState) {
        if liveStates[id]?.waiting != state.waiting {fputs("Mote waiting state: \(state.waiting ?? "none")\n",stderr)}
        liveStates[id]=state
        if let kind=state.waiting,let raw=rawJobs.first(where:{$0.id==id}) {
            let signature=raw.turn+kind+state.requestIDs.joined(separator:":")
            if waitSignatures[id] != signature {var job=raw;job.status=kind;notify(job);selected=id;waitSignatures[id]=signature}
        }else{waitSignatures.removeValue(forKey:id)}
        reconcile();onUpdate?()
    }
    func reconcile(){
        jobs=rawJobs.map { raw in var job=raw;if let kind=liveStates[raw.id]?.waiting {job.status=kind}else if raw.status=="completed",(raw.readReceipt ?? liveStates[raw.id]?.unread) == true {job.status="unread"};return job }.sorted { a,b in
            let aw=["approval","answer"].contains(a.status),bw=["approval","answer"].contains(b.status)
            if aw != bw{return aw};return a.status=="unread" && b.status != "unread"
        }
    }
    func open(_ id:String) { if let url=URL(string:"codex://threads/"+id) { NSWorkspace.shared.open(url) } }
}

struct Dust: View {
    var status:String
    var working:Bool {status=="inProgress"}
    var waiting:Bool {["approval","answer","unread"].contains(status)}
    var body: some View {
        TimelineView(.animation(minimumInterval:0.18,paused: !working && !waiting)) { context in
            let phase=(working || waiting) ? sin(context.date.timeIntervalSince1970*(waiting ? 3:6)) : 0
            Canvas { ctx,size in
                let color=Color(nsColor:.labelColor); let center=CGPoint(x:size.width/2,y:size.height/2+phase*2);let radius=size.width*0.29
                var silhouette=Path()
                for i in 0..<20 {let angle=Double(i)*Double.pi/10;let p=CGPoint(x:center.x+cos(angle)*radius*0.9,y:center.y+sin(angle)*radius*0.83);silhouette.addEllipse(in:CGRect(x:p.x-7,y:p.y-7,width:14,height:14))}
                silhouette.addEllipse(in:CGRect(x:center.x-radius,y:center.y-radius,width:radius*2,height:radius*1.9))
                ctx.fill(silhouette,with:.color(color))
                for dx in [-11.0,11.0] {ctx.fill(Path(ellipseIn:CGRect(x:center.x+dx-5,y:center.y-7,width:waiting ? 13:10,height:waiting ? 16:13)),with:.color(Color(nsColor:.windowBackgroundColor)));ctx.fill(Path(ellipseIn:CGRect(x:center.x+dx,y:center.y-3,width:3,height:5)),with:.color(color))}
                var hand=Path();hand.move(to:CGPoint(x:center.x+radius-1,y:center.y));hand.addLine(to:CGPoint(x:center.x+radius+10,y:center.y+(waiting ? -32+phase*5:12+phase*3)));ctx.stroke(hand,with:.color(color),style:StrokeStyle(lineWidth:5,lineCap:.round))
            }
        }.accessibilityLabel(waiting ? "손을 들고 응답을 기다리는 먼지 요정" : working ? "작업 중인 먼지 요정" : "쉬는 먼지 요정")
    }
}
struct Glass: NSViewRepresentable {
    func makeNSView(context:Context)->NSVisualEffectView {let v=NSVisualEffectView();v.material = .popover;v.blendingMode = .behindWindow;v.state = .active;return v}
    func updateNSView(_ v:NSVisualEffectView,context:Context){}
}
enum Palette {
    static let olive = Color(nsColor: NSColor(name:nil) { appearance in
        appearance.bestMatch(from:[.darkAqua,.aqua]) == .darkAqua ? NSColor(calibratedRed:0.57,green:0.61,blue:0.46,alpha:1) : NSColor(calibratedRed:0.37,green:0.41,blue:0.29,alpha:1)
    })
}
final class MotePanel: NSPanel { override var canBecomeKey:Bool { true }; override func cancelOperation(_ sender:Any?) { orderOut(nil) } }
struct Panel: View {
    @ObservedObject var model:Monitor
    var body: some View {
        VStack(alignment:.leading,spacing:0) {
            HStack {Text("mote.").font(.system(size:24,weight:.semibold,design:.rounded));Text(model.error != nil ? "연결 확인 필요" : model.liveConnected ? "● 실시간 감지":"로컬 기록 · 재연결 중").font(.system(size:11)).foregroundStyle(.secondary);Spacer();Button{model.muted.toggle()}label:{Image(systemName:model.muted ? "bell.slash":"bell")}.buttonStyle(.plain).help("알림 일시 중지")}.padding(.bottom,18)
            HStack {VStack(alignment:.leading,spacing:7){Text("작은 먼지가 챙겨둘게요").font(.system(size:12)).foregroundStyle(.secondary);Text(model.unread>0 && model.waiting==0 ? "미확인 답변이\n\(model.unread)개 있어요." : model.waiting > 0 ? "\(model.waiting)개 작업이\n응답을 기다려요." : model.active > 0 ? "\(model.active)개 작업이\n진행 중이에요." : "지금은 쉬고 있어요.").font(.system(size:25,weight:.semibold)).tracking(-0.7).fixedSize(horizontal:false,vertical:true)};Spacer();Dust(status:model.fairyStatus).frame(width:105,height:105)}.padding(.bottom,15)
            if let error=model.error {Text(error).font(.callout).foregroundStyle(.orange).padding(.bottom,10)}
            HStack {Button("최근 작업"){model.all=false}.tint(model.all ? .secondary:Palette.olive);Button("전체 \(model.jobs.count)"){model.all=true}.tint(model.all ? Palette.olive:.secondary);Spacer();Text("3초마다 확인").font(.system(size:11)).foregroundStyle(.secondary)}.buttonStyle(.borderless).padding(.bottom,12)
            ScrollView {VStack(spacing:3){ForEach(Array(model.jobs.prefix(model.all ? 20:5))){job in Button {model.selected=job.id}label:{HStack(spacing:11){Image(systemName:job.symbol).frame(width:30,height:30).background(job.status == "failed" ? Color.orange.opacity(0.12):Palette.olive.opacity(0.12),in:RoundedRectangle(cornerRadius:9));VStack(alignment:.leading,spacing:4){Text(job.title).font(.system(size:14,weight:.medium)).lineLimit(1);Text("\(job.project) · \(job.label)").font(.system(size:11)).foregroundStyle(.secondary)};Spacer();if job.status=="unread"{Circle().fill(Palette.olive).frame(width:7,height:7).accessibilityLabel("미확인 답변")}}.padding(10).frame(maxWidth:.infinity,alignment:.leading).background(model.chosen?.id == job.id ? Color.primary.opacity(0.055):.clear,in:RoundedRectangle(cornerRadius:11))}.buttonStyle(.plain)}}}.frame(height:190)
            if let job=model.chosen {Divider().padding(.vertical,15);Text(job.label).font(.system(size:12)).foregroundStyle(.secondary);Text(job.title).font(.system(size:17,weight:.semibold)).lineLimit(3).fixedSize(horizontal:false,vertical:true).padding(.top,5);Text(job.status == "unread" ? "답변이 도착했어요. Codex에서 읽으면 미확인 표시가 사라져요." : job.status == "approval" ? "Codex에서 요청한 내용을 확인하고 승인해 주세요." : job.status == "answer" ? "Codex에 답변하면 요정이 다시 작업 상태로 돌아가요." : model.liveConnected ? "승인과 질문 대기를 실시간으로 확인하고 있어요." : "실시간 연결을 기다리고 있어요. 기본 작업 상태는 계속 확인해요.").font(.system(size:12)).foregroundStyle(.secondary).padding(.top,8);Button {model.open(job.id)}label:{HStack {Text("Codex에서 작업 보기");Image(systemName:"arrow.up.right")}.frame(maxWidth:.infinity).padding(.vertical,7)}.buttonStyle(.borderedProminent).tint(Palette.olive).padding(.top,14)}
            Divider().padding(.vertical,14)
            HStack {Button(model.notificationStatus){model.requestNotifications()};Spacer();Button("테스트 알림"){model.notify(Job(id:"test",title:"모트 알림이 정상 작동해요",project:"",status:"completed",turn:UUID().uuidString))};Menu {Button("새로고침"){model.refresh()};Button("종료"){NSApp.terminate(nil)}}label:{Image(systemName:"ellipsis")}}.font(.system(size:11)).buttonStyle(.borderless)
        }.padding(23).frame(width:440).tint(Palette.olive)
    }
}
@MainActor final class AppDelegate:NSObject,NSApplicationDelegate,UNUserNotificationCenterDelegate {
    var didSetup=false;let monitor=Monitor();var item:NSStatusItem!;var panel:MotePanel!;var menuFairy:MenuFairy!
    func applicationDidFinishLaunching(_ notification:Notification){
        guard !didSetup else{return};didSetup=true
        fputs("Mote startup\n",stderr);NSApp.setActivationPolicy(.accessory);UNUserNotificationCenter.current().delegate=self
        item=NSStatusBar.system.statusItem(withLength:NSStatusItem.variableLength)
        item.button?.target=self;item.button?.action=#selector(toggle)
        menuFairy=MenuFairy(button:item.button);menuFairy.update("idle")
        panel=MotePanel(contentRect:NSRect(x:0,y:0,width:440,height:700),styleMask:[.titled,.fullSizeContentView],backing:.buffered,defer:false)
        panel.title="Mote";panel.titleVisibility = .hidden;panel.titlebarAppearsTransparent=true
        panel.isOpaque=false;panel.backgroundColor = .clear;panel.hasShadow=true;panel.level = .floating
        panel.isMovableByWindowBackground=true;panel.hidesOnDeactivate=false
        panel.standardWindowButton(.closeButton)?.isHidden=true;panel.standardWindowButton(.miniaturizeButton)?.isHidden=true;panel.standardWindowButton(.zoomButton)?.isHidden=true
        monitor.onUpdate = {[weak self] in guard let self else{return};self.menuFairy.update(self.monitor.fairyStatus);self.item.button?.title = self.monitor.error != nil ? " 확인 필요" : self.monitor.waiting>0 ? " ! \(self.monitor.waiting)" : self.monitor.unread>0 ? " 답변 \(self.monitor.unread)" : self.monitor.active>0 ? " \(self.monitor.active)":""}
        monitor.start();toggle();fputs("Mote panel ready\n",stderr)
    }
    @objc func toggle(){
        if panel.isVisible {panel.orderOut(nil);return}
        guard let screen=item.button?.window?.screen ?? NSScreen.main else{return}
        // visibleFrame excludes the menu bar; safeAreaInsets also protects notched displays.
        let visible=screen.visibleFrame
        let top=min(visible.maxY,screen.frame.maxY-screen.safeAreaInsets.top)-12
        let height=min(720,top-visible.minY-12)
        let width=min(440,visible.width-24)
        let anchor=item.button?.window?.frame.midX ?? visible.maxX-24
        let x=max(visible.minX+12,min(anchor-width/2,visible.maxX-width-12))
        panel.contentView=NSHostingView(rootView:ScrollView {Panel(model:monitor)}.frame(width:width,height:height).background(Glass()).clipShape(RoundedRectangle(cornerRadius:20)))
        panel.setFrame(NSRect(x:x,y:top-height,width:width,height:height),display:true)
        panel.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
    }
    nonisolated func userNotificationCenter(_ center:UNUserNotificationCenter,willPresent notification:UNNotification,withCompletionHandler completion:@escaping(UNNotificationPresentationOptions)->Void){completion([.banner,.sound])}
    nonisolated func userNotificationCenter(_ center:UNUserNotificationCenter,didReceive response:UNNotificationResponse,withCompletionHandler completion:@escaping()->Void){let id=response.notification.request.content.userInfo["threadID"] as? String;Task{@MainActor in if let id,id != "test"{self.monitor.open(id)}};completion()}
}
if CommandLine.arguments.contains("--diagnose") {do {let jobs=try LocalReader.read();for job in jobs {if CommandLine.arguments.contains("--titles"){print(job.title)};print("\(job.id) \(job.status) unread=\(job.readReceipt.map{String($0)} ?? "unknown")")};print("Detected \(jobs.count) local tasks")}catch{fputs("\(error)\n",stderr);exit(1)}}else{MainActor.assumeIsolated {let app=NSApplication.shared;let delegate=AppDelegate();app.delegate=delegate;app.finishLaunching();delegate.applicationDidFinishLaunching(Notification(name:NSApplication.didFinishLaunchingNotification));withExtendedLifetime(delegate){app.run()}}}
