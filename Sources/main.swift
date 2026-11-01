import AppKit
import SwiftUI
import UserNotifications
import SQLite3
import ServiceManagement
import Darwin

enum MotePreferences {
    static let store:UserDefaults = ProcessInfo.processInfo.environment["MOTE_TEST_SUITE"].flatMap{UserDefaults(suiteName:$0)} ?? .standard
}
struct Job: Identifiable, Equatable {
    var id: String; var title: String; var project: String; var status: String; var turn: String; var readReceipt:Bool? = nil;var waitSince:Date? = nil;var startedAt:Double = 0;var reason:String?=nil
    var label: String { switch status {case "deferred":return "답변 나중에 보기";case "reviewedError":return "오류 확인함";case "unread": return "답변 도착 · 미확인"; case "approval": return "승인 대기"; case "answer": return "답변 대기"; case "inProgress": return "작업 중"; case "completed": return "완료"; case "failed": return "오류"; case "interrupted": return "중단됨"; default: return "확인 필요"} }
    var symbol: String { switch status {case "deferred":return "clock";case "reviewedError":return "checkmark";case "unread": return "envelope.badge"; case "approval": return "hand.raised"; case "answer": return "message"; case "inProgress": return "ellipsis"; case "completed": return "checkmark"; case "failed": return "exclamationmark.triangle"; default: return "questionmark"} }
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
    static func read(currentIDs:Set<String>=[]) throws -> [Job] {
        let home = ProcessInfo.processInfo.environment["CODEX_HOME"] ?? NSHomeDirectory()+"/.codex"
        let files = try FileManager.default.contentsOfDirectory(atPath:home)
        guard let state = files.filter({$0.hasPrefix("state_") && $0.hasSuffix(".sqlite")}).sorted(by:{$0.localizedStandardCompare($1) == .orderedDescending}).first else { throw NSError(domain:"Codex 기록을 찾지 못했어요",code:4) }
        let columns=try query(home+"/"+state,"PRAGMA table_info(threads)").map{$0[1]}
        let titleColumn=columns.contains("name") ? "COALESCE(NULLIF(TRIM(name),''),'')" : "''"
        let threads = try query(home+"/"+state,"SELECT id, \(titleColumn), cwd FROM threads WHERE archived=0 AND agent_path IS NULL ORDER BY updated_at DESC")
        let turns = try query(home+"/thread_history_1.sqlite", "SELECT t.thread_id,t.turn_id,t.status,COALESCE(t.started_at,0) FROM thread_turns t JOIN (SELECT thread_id,MAX(rollout_ordinal) n FROM thread_turns GROUP BY thread_id) latest ON t.thread_id=latest.thread_id AND t.rollout_ordinal=latest.n")
        // Desktop read receipts are authoritative for the published turn. Stream snapshots
        // can retain hasUnreadTurn after the desktop handles a separate read-state event.
        let receiptRows=(try? query(home+"/"+state,"SELECT thread_id, first_unread_turn IS NOT NULL, COALESCE(last_published_turn,'') FROM thread_read_receipts")) ?? []
        let receipts=Dictionary(receiptRows.map{($0[0],$0)},uniquingKeysWith:{_,b in b})
        let lookup = Dictionary(turns.map { ($0[0],$0) }, uniquingKeysWith: { a,b in b })
        return threads.enumerated().compactMap { index,row in
            let t = lookup[row[0]]; var status = t?[2] ?? "unknown"
            // In-progress rows can survive a terminated Codex process. Never invent completion.
            if status == "inProgress", let stamp = Double(t?[3] ?? "0") {
                let seconds = stamp > 10_000_000_000 ? stamp/1000 : stamp
                if Date().timeIntervalSince1970-seconds > 6*3600 { status="unknown" }
            }
            let receipt:Bool?=receipts[row[0]].flatMap{r in r[2] == t?[1] ? r[1] == "1" : nil}
            guard index<20 || t?[2]=="inProgress" || receipt==true || currentIDs.contains(row[0]) else{return nil}
            return Job(id:row[0],title:row[1].isEmpty ? "제목 없는 대화" : row[1],project:URL(fileURLWithPath:row[2]).lastPathComponent,status:status,turn:t?[1] ?? "",readReceipt:receipt,startedAt:{let v=Double(t?[3] ?? "0") ?? 0;return v>10_000_000_000 ? v/1000:v}())
        }
    }
}

@MainActor final class Monitor: ObservableObject {
    @Published var jobs=[Job](); @Published var error: String?; @Published var selected: String? = MotePreferences.store.string(forKey:"currentConversation"); @Published var all=false
    @Published var pinnedIDs:[String] = MotePreferences.store.stringArray(forKey:"workingConversations") ?? MotePreferences.store.string(forKey:"currentConversation").map{[$0]} ?? []
    @Published var notificationStatus="알림 권한 확인 중"; @Published var muted=false
    @Published var liveConnected=false
    @Published var showSettings=false
    @Published var undoPins:[String]?
    @Published var liveIssue:String?
    @Published var lastSync:Date?
    @Published var deferred=MotePreferences.store.dictionary(forKey:"deferredReplies") as? [String:String] ?? [:] {didSet{MotePreferences.store.set(deferred,forKey:"deferredReplies")}}
    let updates=UpdateChecker()
    var completionQueue=[Job]()
    var completionTask:Task<Void,Never>?
    var onNotice:(([Job],String,String)->Void)?
    var onOpenInbox:(()->Void)?
    var alertThreads=[String:Set<String>]()
    var lastSystemReconcile=Date.distantPast
    var menuSummary:String {PresentationPolicy.summary(running:active,waiting:waiting,unread:unread,errors:jobs.filter{$0.status=="failed"}.count)}
    func deferReply(_ job:Job){deferred[job.id]=job.turn;reconcile();onUpdate?()}
    func restoreReply(_ job:Job){deferred.removeValue(forKey:job.id);reconcile();onUpdate?()}
    func cleanCompleted(){
        let remove=Set(currentJobs.filter{["completed","reviewedError","interrupted"].contains($0.status)}.map(\.id))
        guard !remove.isEmpty else{return};undoPins=pinnedIDs;pinnedIDs.removeAll{remove.contains($0)};MotePreferences.store.set(pinnedIDs,forKey:"workingConversations")
    }
    func undoCleanup(){guard let prior=undoPins else{return};pinnedIDs=prior+pinnedIDs.filter{!prior.contains($0)};undoPins=nil;MotePreferences.store.set(pinnedIDs,forKey:"workingConversations")}

    @Published var alertDisplay=MotePreferences.store.string(forKey:"alertDisplay") ?? "cursor" {didSet{MotePreferences.store.set(alertDisplay,forKey:"alertDisplay")}}
    let displayAlerts=DisplayAlerts()
    @Published var pauseUntil:Date? = MotePreferences.store.object(forKey:"pauseUntil") as? Date
    @Published var completionAlerts=MotePreferences.store.object(forKey:"completionAlerts") as? Bool ?? true {didSet{MotePreferences.store.set(completionAlerts,forKey:"completionAlerts")}}
    @Published var attentionAlerts=MotePreferences.store.object(forKey:"attentionAlerts") as? Bool ?? true {didSet{MotePreferences.store.set(attentionAlerts,forKey:"attentionAlerts")}}
    @Published var errorAlerts=MotePreferences.store.object(forKey:"errorAlerts") as? Bool ?? true {didSet{MotePreferences.store.set(errorAlerts,forKey:"errorAlerts")}}
    @Published var attentionSound=MotePreferences.store.object(forKey:"attentionSound") as? Bool ?? true {didSet{MotePreferences.store.set(attentionSound,forKey:"attentionSound")}}
    @Published var completionSound=MotePreferences.store.object(forKey:"completionSound") as? Bool ?? false {didSet{MotePreferences.store.set(completionSound,forKey:"completionSound")}}
    @Published var loginEnabled=SMAppService.mainApp.status == .enabled
    @Published var settingsError:String?
    var currentPolicy=CurrentConversationPolicy(started:MotePreferences.store.double(forKey:"currentTurnStarted"),turnID:MotePreferences.store.string(forKey:"currentTurnID") ?? "")
    func followNewTurn(id:String,turn:String,started:Double){
        if let next=currentPolicy.observe(id:id,turn:turn,startedAt:started){
            makeCurrent(next);MotePreferences.store.set(currentPolicy.started,forKey:"currentTurnStarted");MotePreferences.store.set(currentPolicy.turnID,forKey:"currentTurnID")
        }
    }
    var ledger=NotificationLedger(sent:MotePreferences.store.dictionary(forKey:"notificationLedger") as? [String:Double] ?? [:])
    var waitTimes=MotePreferences.store.dictionary(forKey:"waitTimes") as? [String:Date] ?? [:]
    var dismissedErrors=MotePreferences.store.stringArray(forKey:"dismissedErrors") ?? []
    var paused:Bool {pauseUntil.map{$0>Date()} ?? false}
    var attentionJobs:[Job] {jobs.filter{["approval","answer","unread","failed"].contains($0.status)}}
    var runningJobs:[Job] {jobs.filter{$0.status=="inProgress"}}
    var currentJobs:[Job] {let lookup=Dictionary(uniqueKeysWithValues:jobs.map{($0.id,$0)});return pinnedIDs.compactMap{lookup[$0]}}
    var inboxJobs:[Job] {attentionJobs.filter{!pinnedIDs.contains($0.id)}}
    var otherRunning:[Job] {runningJobs.filter{!pinnedIDs.contains($0.id)}}
    func makeCurrent(_ id:String){selected=id;pinnedIDs=WorkingConversations.adding(id,to:pinnedIDs);MotePreferences.store.set(pinnedIDs,forKey:"workingConversations");MotePreferences.store.set(id,forKey:"currentConversation")}
    func removeCurrent(_ id:String){undoPins=pinnedIDs;pinnedIDs=WorkingConversations.removing(id,from:pinnedIDs);MotePreferences.store.set(pinnedIDs,forKey:"workingConversations")}
    func pause(){pauseUntil=Date().addingTimeInterval(1800);MotePreferences.store.set(pauseUntil,forKey:"pauseUntil")}
    func resume(){pauseUntil=nil;MotePreferences.store.removeObject(forKey:"pauseUntil")}
    func setLogin(_ enabled:Bool){do{if enabled{try SMAppService.mainApp.register()}else{try SMAppService.mainApp.unregister()};loginEnabled=SMAppService.mainApp.status == .enabled;settingsError=SMAppService.mainApp.status == .requiresApproval ? "시스템 설정의 로그인 항목에서 허용해 주세요.":nil}catch{settingsError="자동 실행 설정 실패: \(error.localizedDescription)";loginEnabled=SMAppService.mainApp.status == .enabled}}
    func dismissError(_ job:Job){dismissedErrors.append(job.id+job.turn);dismissedErrors=Array(dismissedErrors.suffix(500));MotePreferences.store.set(dismissedErrors,forKey:"dismissedErrors");reconcile();onUpdate?()}

    let live=LiveObserver();var rawJobs=[Job]();var liveStates=[String:LiveState]();var waitSignatures=[String:String]()
    var waiting:Int {jobs.filter{["approval","answer"].contains($0.status)}.count}
    var unread:Int {jobs.filter{$0.status=="unread"}.count}
    var fairyStatus:String {waiting>0 ? (jobs.first{["approval","answer"].contains($0.status)}?.status ?? "answer") : unread>0 ? "unread" : jobs.contains{$0.status=="failed"} ? "failed" : active>0 ? "inProgress":"idle"}
    let monitoringStarted=Date().timeIntervalSince1970
    var baseline=false; var previous=[String:Job](); var timer: Timer?; var reading=false
    var onUpdate: (() -> Void)?
    var active: Int { jobs.filter{$0.status=="inProgress"}.count }
    var chosen: Job? { jobs.first{$0.id==selected} ?? jobs.first }
    func start() {
        live.onDiagnostic = {[weak self] message in Task{@MainActor in guard let self else{return};self.liveIssue=message;if message != nil{self.liveStates.removeAll();self.reconcile();self.onUpdate?()}}}
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
    func notify(_ job:Job,requests:[String]=[],test:Bool=false) {
        guard test || job.status != "completed" || job.readReceipt != false else{return}
        let attention=["approval","answer"].contains(job.status)
        guard test || (!muted && !paused && (attention ? attentionAlerts : job.status=="failed" ? errorAlerts:completionAlerts)) else{return}
        let key=NotificationLedger.key(thread:job.id,turn:job.turn,kind:job.status,requests:requests)
        guard test || ledger.claim(key) else{return}
        if !test{MotePreferences.store.set(ledger.sent,forKey:"notificationLedger")}
        let content=UNMutableNotificationContent()
        content.title=test ? "모트 · 테스트 알림" : ["approval":"모트 · 승인이 필요해요","answer":"모트 · 답변을 기다리고 있어요","failed":"모트 · 작업에 문제가 생겼어요"][job.status] ?? "모트 · 작업이 끝났어요"
        content.body=String(job.title.prefix(100))+(job.reason.map{"\n"+$0} ?? "");if test || (attention ? attentionSound:completionSound){content.sound = .default};content.userInfo=["threadID":job.id]
        if job.status=="completed" && !test {
            completionQueue.append(job)
            if completionTask==nil {completionTask=Task{[weak self] in try? await Task.sleep(nanoseconds:1_500_000_000);guard !Task.isCancelled,let self else{return};self.flushCompletions()}}
            return
        }
        deliver([job],title:content.title,body:content.body,sound:test || (attention ? attentionSound:completionSound),identifier:key)
    }
    func flushCompletions(){
        let pending=completionQueue;completionQueue=[];completionTask=nil
        guard !pending.isEmpty,!paused,!muted,completionAlerts else{return}
        let title=pending.count==1 ? "모트 · 작업이 끝났어요":"모트 · 작업 \(pending.count)개가 끝났어요"
        deliver(pending,title:title,body:pending.prefix(3).map(\.title).joined(separator:" · "),sound:completionSound,identifier:"complete:"+pending.map{$0.id+$0.turn}.sorted().joined(separator:":"))
    }
    func deliver(_ notices:[Job],title:String,body:String,sound:Bool,identifier:String){
        if let onNotice {onNotice(notices,title,body);return}
        let threads=Set(notices.map(\.id));alertThreads[identifier]=threads
        if alertDisplay != "system" {
            displayAlerts.show(title:title,body:body,mode:alertDisplay,sound:sound,threads:threads){[weak self] in
                guard let self else{return};if notices.count==1,let job=notices.first,job.id != "test"{self.open(job.id)}else{self.onOpenInbox?()}
            };return
        }
        let content=UNMutableNotificationContent();content.title=title;content.body=body
        if sound{content.sound = .default};content.userInfo=["threadID":notices.count==1 ? notices[0].id:"batch","threadIDs":Array(threads)]
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier:identifier,content:content,trigger:nil)){error in
            if error != nil{Task{@MainActor in self.settingsError="알림 전송에 실패했어요. 알림 허용 설정을 확인해 주세요."}}
        }
    }
    func clearResolvedAlerts(){
        let resolved=Set(jobs.filter{job in
            ["inProgress","interrupted","reviewedError","deferred"].contains(job.status) || (job.status=="completed" && job.readReceipt==false)
        }.map(\.id))
        completionQueue.removeAll{notice in jobs.contains{job in job.id==notice.id && ((job.status=="completed" && job.readReceipt==false) || job.turn != notice.turn)}}
        displayAlerts.cancel(threads:resolved)
        let identifiers=alertThreads.filter{PresentationPolicy.resolvedGroup($0.value,by:resolved)}.map(\.key)
        for id in identifiers{alertThreads.removeValue(forKey:id)}
        if !identifiers.isEmpty{UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers:identifiers);UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers:identifiers)}
        if alertDisplay=="system",Date().timeIntervalSince(lastSystemReconcile)>10{
            lastSystemReconcile=Date()
            UNUserNotificationCenter.current().getDeliveredNotifications{notifications in
                let remove=notifications.filter{note in
                    let ids=Set(note.request.content.userInfo["threadIDs"] as? [String] ?? [])
                    return PresentationPolicy.resolvedGroup(ids,by:resolved)
                }.map{$0.request.identifier}
                if !remove.isEmpty{UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers:remove)}
            }
        }
    }
    func refresh() {
        guard !reading else{return}; reading=true
        let currentIDs=Set(pinnedIDs)
        Task.detached { let result = Result { try LocalReader.read(currentIDs:currentIDs) }; await self.apply(result) }
    }
    func apply(_ result:Result<[Job],Error>) {
        reading=false
        switch result {case .success(let found):
            if baseline {for j in found where previous[j.id]?.turn != j.turn && j.startedAt>=monitoringStarted-3 {makeCurrent(j.id)}}
            if baseline { for j in found { if let old=previous[j.id], ["completed","failed"].contains(j.status), (j.turn != old.turn || old.status == "inProgress") { notify(j) } } }
            previous=Dictionary(uniqueKeysWithValues:found.map{($0.id,$0)});rawJobs=found;lastSync=Date()
            if !baseline {for job in found.reversed() where job.status=="inProgress" && !pinnedIDs.contains(job.id){makeCurrent(job.id)}}
            let chronological=found.sorted{a,b in a.startedAt==b.startedAt ? a.turn<b.turn:a.startedAt<b.startedAt}
            if currentPolicy.started==0 {if let newest=chronological.last{followNewTurn(id:newest.id,turn:newest.turn,started:newest.startedAt)}}
            else{for job in chronological{followNewTurn(id:job.id,turn:job.turn,started:job.startedAt)}}
            live.observe(found.map(\.id));reconcile();error=nil;baseline=true
        case .failure(let e): error=e.localizedDescription }
        onUpdate?()
    }
    func receive(_ id:String,_ state:LiveState) {
        let old=liveStates[id]
        if let latest=state.latestTurn,let raw=rawJobs.first(where:{$0.id==id}),latest.id != raw.turn,latest.started/1000 < raw.startedAt {return}
        if let latest=state.latestTurn,rawJobs.contains(where:{$0.id==id}){followNewTurn(id:id,turn:latest.id,started:latest.started/1000)}
        if let latest=state.latestTurn,["completed","failed"].contains(latest.status),let prior=old?.latestTurn,
            latest.id != prior.id || latest.status != prior.status,let raw=rawJobs.first(where:{$0.id==id}) {
            var finished=raw;finished.turn=latest.id;finished.status=latest.status;finished.readReceipt = raw.turn == latest.id ? raw.readReceipt:nil;notify(finished)
            refresh()
        }
        if liveStates[id]?.waiting != state.waiting {fputs("Mote waiting state: \(state.waiting ?? "none")\n",stderr)}
        liveStates[id]=state
        if let kind=state.waiting,let raw=rawJobs.first(where:{$0.id==id}) {
            let signature=(state.latestTurn?.id ?? raw.turn)+kind+state.requestIDs.sorted().joined(separator:":")
            if waitSignatures[id] != signature {var job=raw;job.turn=state.latestTurn?.id ?? raw.turn;job.status=kind;job.reason=state.requestReasons.values.sorted().first;notify(job,requests:state.requestIDs);waitSignatures[id]=signature}
        }else{waitSignatures.removeValue(forKey:id)}
        reconcile();onUpdate?()
    }
    func reconcile(){
        jobs=rawJobs.map {raw in
            var job=raw
            if let liveState=liveStates[raw.id] {
                // Never let an old stream snapshot overwrite a newer persisted turn.
                let latest=liveState.latestTurn
                let usable=latest == nil || latest?.id == raw.turn || (latest!.started/1000 >= raw.startedAt)
                if usable {
                    if let latest,latest.id != raw.turn {
                        job.turn=latest.id;job.startedAt=latest.started/1000;job.readReceipt=nil
                        job.status=latest.status
                    } else if let latest,["completed","failed","interrupted"].contains(latest.status) {
                        job.status=latest.status
                    }
                    if let kind=liveState.waiting {job.status=kind;job.reason=liveState.requestReasons.values.sorted().first}
                    else if liveState.runtime["type"] as? String == "active",latest == nil || latest?.status == "inProgress" {job.status="inProgress"}
                    if job.status=="completed",(job.readReceipt ?? liveState.unread)==true {job.status="unread"}
                }
            }
            if job.status=="completed",job.readReceipt==true{job.status="unread"}
            if job.status=="unread",PresentationPolicy.isDeferred(thread:job.id,turn:job.turn,records:deferred){job.status="deferred"}
            if ["approval","answer"].contains(job.status){
                let state=liveStates[raw.id]
                let key=NotificationLedger.key(thread:raw.id,turn:state?.latestTurn?.id ?? raw.turn,kind:job.status,requests:state?.requestIDs ?? [])
                if waitTimes[key]==nil{waitTimes[key]=Date()};job.waitSince=waitTimes[key]
            }
            if job.status=="failed",dismissedErrors.contains(job.id+job.turn){job.status="reviewedError"}
            return job
        }.enumerated().sorted{a,b in
            func rank(_ status:String)->Int{switch status{case "approval","answer":return 0;case "failed":return 1;case "unread":return 2;case "inProgress":return 3;default:return 4}}
            let ar=rank(a.element.status),br=rank(b.element.status)
            return ar==br ? a.offset<b.offset:ar<br
        }.map(\.element)
        if waitTimes.count>500 {waitTimes=Dictionary(uniqueKeysWithValues:waitTimes.sorted{$0.value>$1.value}.prefix(300).map{($0.key,$0.value)})}
        MotePreferences.store.set(waitTimes,forKey:"waitTimes");clearResolvedAlerts()
    }
    var openURL:(URL)->Bool = {NSWorkspace.shared.open($0)}
    static func conversationURL(_ id:String)->URL? {
        guard !id.isEmpty,id.unicodeScalars.allSatisfy({CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_"}) else{return nil}
        var parts=URLComponents();parts.scheme="codex";parts.host="threads";parts.path="/"+id
        parts.queryItems=[URLQueryItem(name:"hostId",value:"local")]
        return parts.url
    }
    func open(_ id:String) {
        guard let url=Self.conversationURL(id) else{error="대화 링크가 올바르지 않아요.";onUpdate?();return}
        if openURL(url){makeCurrent(id);refresh()}else{error="Codex에서 대화를 열지 못했어요. Codex 설치와 실행 상태를 확인해 주세요.";onUpdate?()}
        // Opening a link is not proof that a reply was read; only Codex receipts clear it.
    }

}

struct Dust: View {
    var status:String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body:some View{
        TimelineView(.animation(minimumInterval:0.2,paused:status=="idle" || reduceMotion)){context in
            let frame=reduceMotion ? 0:Int(context.date.timeIntervalSince1970*5)%4
            Image(nsImage:MenuFairy.image(state:status,frame:frame)).resizable().interpolation(.high).scaledToFit()
        }.accessibilityLabel(["approval":"승인을 기다리는 요정","answer":"답변을 기다리는 요정","unread":"새 답변을 배달하는 요정","failed":"오류를 알리는 요정","inProgress":"작업 중인 요정"][status] ?? "쉬는 요정")
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
struct RunningIndicator:View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body:some View {
        TimelineView(.animation(minimumInterval:0.1,paused:reduceMotion)){context in
            let phase=reduceMotion ? 0:context.date.timeIntervalSince1970
            ZStack {
                Circle().stroke(Palette.olive.opacity(0.14),lineWidth:2)
                Circle().trim(from:0,to:0.28).stroke(Palette.olive,style:StrokeStyle(lineWidth:2,lineCap:.round))
                    .rotationEffect(.degrees(reduceMotion ? -90:phase*130))
            }.frame(width:17,height:17)
        }.accessibilityLabel("작업 진행 중")
    }
}
struct RunningCaption:View {
    var project:String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body:some View {
        TimelineView(.animation(minimumInterval:0.25,paused:reduceMotion)){context in
            let step=Int(context.date.timeIntervalSince1970*3)%3
            HStack(spacing:5){Text("\(project) · 작업 중");HStack(spacing:3){ForEach(0..<3){i in
                Circle().fill(Palette.olive.opacity(reduceMotion || i==step ? 0.85:0.20)).frame(width:3,height:3)
            }}.accessibilityHidden(true)}.font(.caption).foregroundStyle(.secondary)
        }
    }
}
struct Panel:View {
    @ObservedObject var model:Monitor
    var headline:String {
        if model.waiting>0{return "\(model.waiting)개 작업이\n응답을 기다려요."}
        if model.unread>0{return "미확인 답변이\n\(model.unread)개 있어요."}
        if model.jobs.contains(where:{$0.status=="failed"}){return "확인이 필요한\n오류가 있어요."}
        return model.active>0 ? "\(model.active)개 작업이\n진행 중이에요.":"지금은 쉬고 있어요."
    }
    var body:some View {
        VStack(alignment:.leading,spacing:16){
            HStack{Text("mote.").font(.system(size:24,weight:.semibold,design:.rounded));Text(model.liveIssue != nil ? "기본 기록 감지":model.liveConnected ? "● 실시간 감지":"재연결 중").font(.caption).foregroundStyle(.secondary);Spacer();Button{model.showSettings.toggle()}label:{Image(systemName:"slider.horizontal.3")}.buttonStyle(.plain).accessibilityLabel("설정")}
            if model.showSettings{settings}else{
                HStack{VStack(alignment:.leading,spacing:7){Text("작은 먼지가 챙겨둘게요").font(.caption).foregroundStyle(.secondary);Text(headline).font(.system(size:25,weight:.semibold)).fixedSize(horizontal:false,vertical:true)};Spacer();Dust(status:model.fairyStatus).frame(width:100,height:95)}
                if !model.currentJobs.isEmpty {
                    HStack{Label("작업 중인 대화 \(model.currentJobs.count)",systemImage:"pin.fill").font(.caption).foregroundStyle(.secondary);Spacer();Button("완료 정리"){model.cleanCompleted()}.font(.system(size:11)).buttonStyle(.borderless)}
                    VStack(spacing:5){ForEach(model.currentJobs){current in
                        HStack(spacing:5){row(current);Button{model.removeCurrent(current.id)}label:{Image(systemName:"xmark").font(.system(size:10)).frame(width:25,height:32)}.buttonStyle(.plain).foregroundStyle(.secondary).help("작업 목록에서 빼기 · 대화는 삭제하지 않아요")}
                    }}
                }
                HStack{Button("확인할 작업 \(model.attentionJobs.count)"){model.all=false}.fontWeight(model.all ? .regular:.semibold);Button("전체 \(model.jobs.count)"){model.all=true}.fontWeight(model.all ? .semibold:.regular);Spacer()}.buttonStyle(.borderless)
                VStack(alignment:.leading,spacing:4){
                    if model.all{ForEach(model.jobs.filter{!model.pinnedIDs.contains($0.id)}){row($0)}}else{
                        if model.attentionJobs.isEmpty{Label("지금 확인할 작업은 없어요",systemImage:"checkmark.circle").foregroundStyle(.secondary).padding(.vertical,20)}
                        ForEach(model.inboxJobs){row($0)}
                        if !model.otherRunning.isEmpty{Text("진행 중 \(model.active)").font(.caption).foregroundStyle(.secondary).padding(.top,15);ForEach(model.otherRunning){row($0)}}

                    }
                }
            }
            if model.undoPins != nil{HStack{Text("작업 목록을 정리했어요");Spacer();Button("되돌리기"){model.undoCleanup()}}.font(.caption).foregroundStyle(.secondary)}
            if let issue=model.liveIssue{Text(issue).font(.caption).foregroundStyle(.orange)}
            if let error=model.error{Text(error).font(.caption).foregroundStyle(.orange)}
            if let message=model.settingsError{Text(message).font(.caption).foregroundStyle(.secondary)}
            Divider()
            HStack{Button(model.notificationStatus){model.requestNotifications()};Spacer();Menu{Button("새로고침"){model.refresh()};Button(model.paused ? "알림 다시 켜기":"30분 동안 알림 쉬기"){if model.paused{model.resume()}else{model.pause()}};Button("테스트 알림"){model.notify(Job(id:"test",title:"모트 알림이 정상 작동해요",project:"",status:"completed",turn:UUID().uuidString),test:true)};Button("종료"){NSApp.terminate(nil)}}label:{Image(systemName:"ellipsis")}}.font(.caption).buttonStyle(.borderless)
            if model.paused,let until=model.pauseUntil{HStack{Text("알림 쉬는 중 · \(until.formatted(date:.omitted,time:.shortened))까지");Spacer();Button("다시 켜기"){model.resume()}}.font(.caption).foregroundStyle(.secondary)}
        }.padding(23).frame(width:440).tint(Palette.olive)
    }
    func row(_ job:Job)->some View {
        Button{model.open(job.id)}label:{
            HStack(spacing:11){Group{if job.status=="inProgress"{RunningIndicator()}else{Image(systemName:job.symbol)}}.frame(width:32,height:32).background(job.status=="failed" ? Color.orange.opacity(0.12):Palette.olive.opacity(0.10),in:RoundedRectangle(cornerRadius:9))
                VStack(alignment:.leading,spacing:4){Text(job.title).font(.system(size:14,weight:.medium)).lineLimit(1);if job.status=="inProgress"{RunningCaption(project:job.project)}else{Text("\(job.project) · \(job.label)").font(.caption).foregroundStyle(.secondary)}
                    if let reason=job.reason{Text(reason).font(.caption).foregroundStyle(Palette.olive)}
                    if let since=job.waitSince{TimelineView(.periodic(from:.now,by:30)){context in Text("기다린 지 \(max(0,Int(context.date.timeIntervalSince(since)/60)))분 · 감지 시점 기준").font(.system(size:11)).foregroundStyle(.secondary)}}
                };Spacer();if job.status=="unread"{Circle().fill(Palette.olive).frame(width:7,height:7)};Image(systemName:"arrow.up.right").font(.system(size:11)).foregroundStyle(.tertiary)
            }.padding(11).frame(maxWidth:.infinity,alignment:.leading).background(Color.primary.opacity(0.035),in:RoundedRectangle(cornerRadius:11))
        }.buttonStyle(.plain).help("Codex에서 \(job.title) 열기").contextMenu{Button("작업 중인 대화에 추가"){model.makeCurrent(job.id)};
            if job.status=="unread"{Button("답변 나중에 보기"){model.deferReply(job)}}
            if job.status=="deferred"{Button("미확인 답변으로 다시 표시"){model.restoreReply(job)}};if job.status=="failed"{Button("오류 확인했어요"){model.dismissError(job)}}}
    }
    var settings:some View {
        VStack(alignment:.leading,spacing:16){
            Text("알림과 실행").font(.title3.weight(.semibold))
            Picker("알림 표시 화면",selection:$model.alertDisplay){Text("마우스가 있는 화면").tag("cursor");Text("주 모니터").tag("main");Text("macOS 기본 알림").tag("system");ForEach(NSScreen.screens,id:\.self){screen in
                Text(screen.localizedName).tag("display:"+((screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.stringValue ?? ""))
            }}
            Text(model.alertDisplay == "system" ? "macOS 알림 설정과 집중 모드를 따릅니다.":"모트 알림은 집중 모드와 별도로 표시돼요. 입력 중인 창의 포커스는 유지돼요.").font(.caption).foregroundStyle(.secondary)
            Button("이 화면 설정으로 테스트 알림"){model.notify(Job(id:"test",title:"모트가 작업 화면으로 찾아왔어요",project:"",status:"completed",turn:UUID().uuidString),test:true)}
            Toggle("로그인 시 모트 실행",isOn:Binding(get:{model.loginEnabled},set:{model.setLogin($0)}))
            Divider()
            Toggle("승인·질문 알림",isOn:$model.attentionAlerts)
            Toggle("승인·질문 알림 소리",isOn:$model.attentionSound)
            Toggle("작업 완료 알림",isOn:$model.completionAlerts)
            Toggle("완료·오류 알림 소리",isOn:$model.completionSound)
            Toggle("오류 알림",isOn:$model.errorAlerts)
            Button(model.paused ? "알림 다시 켜기":"30분 동안 알림 쉬기"){if model.paused{model.resume()}else{model.pause()}}
            Text("작업 상태는 알림을 쉬는 동안에도 계속 표시돼요.").font(.caption).foregroundStyle(.secondary)
            Text("자동 실행은 앱을 고정된 위치에 두고 설정하세요.").font(.caption).foregroundStyle(.secondary)
            Divider()
            DiagnosticsView(model:model,updates:model.updates)
        }.toggleStyle(.switch).padding(.vertical,8)
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
        monitor.onUpdate = {[weak self] in guard let self else{return};self.menuFairy.update(self.monitor.fairyStatus);self.item.button?.title = self.monitor.error != nil ? " 확인 필요" : " "+self.monitor.menuSummary}
        monitor.onOpenInbox = {[weak self] in guard let self else{return};if !self.panel.isVisible{self.toggle()}}
        monitor.start();toggle();fputs("Mote panel ready\n",stderr)
    }
    @objc func toggle(){
        if panel.isVisible {panel.orderOut(nil);return}
        guard let screen=item.button?.window?.screen ?? NSScreen.main else{return}
        // visibleFrame excludes the menu bar; safeAreaInsets also protects notched displays.
        let visible=screen.visibleFrame
        let top=min(visible.maxY,screen.frame.maxY-screen.safeAreaInsets.top)-12
        let height=min(650,top-visible.minY-12)
        let width=min(440,visible.width-24)
        let anchor=item.button?.window?.frame.midX ?? visible.maxX-24
        let x=max(visible.minX+12,min(anchor-width/2,visible.maxX-width-12))
        panel.contentView=NSHostingView(rootView:ScrollView {Panel(model:monitor)}.frame(width:width,height:height).background(Glass()).clipShape(RoundedRectangle(cornerRadius:20)))
        panel.setFrame(NSRect(x:x,y:top-height,width:width,height:height),display:true)
        panel.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
    }
    nonisolated func userNotificationCenter(_ center:UNUserNotificationCenter,willPresent notification:UNNotification,withCompletionHandler completion:@escaping(UNNotificationPresentationOptions)->Void){completion([.banner,.sound])}
    nonisolated func userNotificationCenter(_ center:UNUserNotificationCenter,didReceive response:UNNotificationResponse,withCompletionHandler completion:@escaping()->Void){let id=response.notification.request.content.userInfo["threadID"] as? String;Task{@MainActor in if id=="batch"{self.monitor.onOpenInbox?()}else if let id,id != "test"{self.monitor.open(id)}};completion()}
}
if CommandLine.arguments.contains("--diagnose") {do {let jobs=try LocalReader.read();for job in jobs {if CommandLine.arguments.contains("--titles"){print(job.title)};print("\(job.id) \(job.status) unread=\(job.readReceipt.map{String($0)} ?? "unknown")")};print("Detected \(jobs.count) local tasks")}catch{fputs("\(error)\n",stderr);exit(1)}}else{MainActor.assumeIsolated {let lockURL=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("Mote")
try? FileManager.default.createDirectory(at:lockURL,withIntermediateDirectories:true)
let instanceFD=Darwin.open(lockURL.appendingPathComponent("instance.lock").path,O_CREAT|O_RDWR,0o600)
guard instanceFD>=0,flock(instanceFD,LOCK_EX|LOCK_NB)==0 else{exit(0)}
let app=NSApplication.shared;let delegate=AppDelegate();app.delegate=delegate;app.finishLaunching();delegate.applicationDidFinishLaunching(Notification(name:NSApplication.didFinishLaunchingNotification));withExtendedLifetime(delegate){app.run()}}}
