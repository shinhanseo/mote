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
    var label: String { switch status {case "deferred":return L10n.text("답변 나중에 보기");case "reviewedError":return L10n.text("오류 확인함");case "unread": return L10n.text("답변 도착 · 미확인"); case "approval": return L10n.text("승인 대기"); case "answer": return L10n.text("답변 대기"); case "inProgress": return L10n.text("작업 중"); case "completed": return L10n.text("완료"); case "failed": return L10n.text("오류"); case "interrupted": return L10n.text("중단됨"); default: return L10n.text("확인 필요")} }
    var symbol: String { switch status {case "deferred":return "clock";case "reviewedError":return "checkmark";case "unread": return "envelope.badge"; case "approval": return "hand.raised"; case "answer": return "message"; case "inProgress": return "ellipsis"; case "completed": return "checkmark"; case "failed": return "exclamationmark.triangle"; default: return "questionmark"} }
}
struct LocalReader {
    static func failure(_ message:String, code:Int, detail:String="")->NSError {
        let text=L10n.text(message)+(detail.isEmpty ? "":" · "+detail)
        return NSError(domain:"Mote.LocalReader",code:code,userInfo:[NSLocalizedDescriptionKey:text])
    }
    static func databaseFailure(_ db:OpaquePointer?,path:String,stage:String)->NSError {
        let code=sqlite3_extended_errcode(db)
        let message=String(cString:sqlite3_errmsg(db)).lowercased()
        // Classify locally; never copy raw SQLite errors, which can contain schema text.
        let kind:String
        switch code & 255 {
        case SQLITE_BUSY,SQLITE_LOCKED:kind="busy"
        case SQLITE_CORRUPT:kind="corrupt"
        case SQLITE_NOTADB:kind="not-a-database"
        case SQLITE_AUTH,SQLITE_PERM,SQLITE_CANTOPEN,SQLITE_READONLY:kind="access"
        case SQLITE_IOERR:kind="io"
        default:kind=message.contains("no such table") ? "missing-table":message.contains("no such column") ? "missing-column":message.contains("no such function") ? "unsupported-function":message.contains("no such collation") ? "unsupported-collation":message.contains("malformed database schema") ? "invalid-schema":"sql-error"
        }
        return failure("Codex 기록을 읽지 못했어요",code:Int(code),detail:URL(fileURLWithPath:path).lastPathComponent+" [SQLite \(code), \(stage), \(kind)]")
    }
    static func query(_ path: String, _ sql: String) throws -> [[String]] {
        var db: OpaquePointer?
        let opened=sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil)
        defer {if let db {sqlite3_close(db)}}
        guard opened==SQLITE_OK else {throw databaseFailure(db,path:path,stage:"open")}
        sqlite3_busy_timeout(db, 1000)
        var stmt: OpaquePointer?
        defer {if let stmt {sqlite3_finalize(stmt)}}
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil)==SQLITE_OK else {throw databaseFailure(db,path:path,stage:"prepare")}
        var rows = [[String]]()
        while true {let step=sqlite3_step(stmt);if step==SQLITE_DONE{break};guard step==SQLITE_ROW else{throw databaseFailure(db,path:path,stage:"step")}
            rows.append((0..<sqlite3_column_count(stmt)).map {i in sqlite3_column_text(stmt,i).map{String(cString:$0)} ?? ""})
        };return rows
    }
    // Schema only: never includes titles, prompts, IDs, row data or home paths.
    static func diagnosticSummary()->String {
        let home=ProcessInfo.processInfo.environment["CODEX_HOME"] ?? NSHomeDirectory()+"/.codex"
        let files=(try? FileManager.default.contentsOfDirectory(atPath:home)) ?? []
        var lines=["SQLite \(String(cString:sqlite3_libversion()))", "Mote \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown")", "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)"]
        for prefix in ["state_","thread_history_"] {
            guard let name=files.filter({$0.hasPrefix(prefix) && $0.hasSuffix(".sqlite")}).sorted(by:{$0.localizedStandardCompare($1) == .orderedDescending}).first else {lines.append(prefix+"*: missing");continue}
            for table in (prefix=="state_" ? ["threads","thread_read_receipts"]:["thread_turns"]) {
                do {let columns=try query(home+"/"+name,"PRAGMA table_info(\(table))").map{$0[1]};lines.append(name+" / "+table+": "+columns.joined(separator:","))}
                catch {lines.append(name+" / "+table+": "+error.localizedDescription)}
            }
        }
        if let result=try? snapshot(),let warning=result.warning {lines.append("History read: "+warning)}
        return lines.joined(separator:"\n")
    }
    struct Snapshot {var jobs:[Job];var warning:String?}
    static func read(currentIDs:Set<String>=[]) throws -> [Job] {try snapshot(currentIDs:currentIDs).jobs}
    static func snapshot(currentIDs:Set<String>=[]) throws -> Snapshot {
        let home = ProcessInfo.processInfo.environment["CODEX_HOME"] ?? NSHomeDirectory()+"/.codex"
        let files = try FileManager.default.contentsOfDirectory(atPath:home)
        guard let state = files.filter({$0.hasPrefix("state_") && $0.hasSuffix(".sqlite")}).sorted(by:{$0.localizedStandardCompare($1) == .orderedDescending}).first else { throw failure("Codex 기록을 찾지 못했어요",code:4) }
        let columns=try query(home+"/"+state,"PRAGMA table_info(threads)").map{$0[1]}
        let titleColumn=columns.contains("name") ? "COALESCE(NULLIF(TRIM(name),''),'')" : "''"
        guard columns.contains("id") else {throw failure("이 Codex 기록 구조는 아직 지원하지 않아요. 연결 상태에서 진단 정보를 확인해 주세요.",code:2,detail:state+": threads.id")}
        let cwd=columns.contains("cwd") ? "COALESCE(cwd,'')":"''"
        var filters=[String]()
        if columns.contains("archived"){filters.append("COALESCE(archived,0)=0")}
        if columns.contains("agent_path"){filters.append("agent_path IS NULL")}
        let condition=filters.isEmpty ? "":" WHERE "+filters.joined(separator:" AND ")
        let order=columns.contains("updated_at") ? "updated_at DESC, id":"id"
        let threads = try query(home+"/"+state,"SELECT id, \(titleColumn), \(cwd) FROM threads\(condition) ORDER BY \(order)")
        var turns=[[String]]();var warning:String?
        do {
        guard let history=files.filter({$0.hasPrefix("thread_history_") && $0.hasSuffix(".sqlite")}).sorted(by:{$0.localizedStandardCompare($1) == .orderedDescending}).first else {
            throw failure("Codex 대화 상태 기록이 없어요. Codex 앱에서 대화를 시작한 뒤 다시 확인해 주세요.",code:6)
        }
        let historyPath=home+"/"+history
        let turnColumns=try query(historyPath,"PRAGMA table_info(thread_turns)").map{$0[1]}
        let required=["thread_id","turn_id","status","rollout_ordinal"]
        guard required.allSatisfy({turnColumns.contains($0)}) else {
            throw failure("이 Codex 기록 구조는 아직 지원하지 않아요. 연결 상태에서 진단 정보를 확인해 주세요.",code:2,detail:history+": thread_turns")
        }
        let started=turnColumns.contains("started_at") ? "COALESCE(t.started_at,0)":"0"
        turns = try query(historyPath, "SELECT t.thread_id,t.turn_id,t.status,\(started) FROM thread_turns t JOIN (SELECT thread_id,MAX(rollout_ordinal) n FROM thread_turns GROUP BY thread_id) latest ON t.thread_id=latest.thread_id AND t.rollout_ordinal=latest.n")
        }catch {warning=L10n.text("대화 목록만 읽었어요. 작업 상태는 실시간 연결이 필요해요.")+" "+error.localizedDescription}
        // Desktop read receipts are authoritative for the published turn. Stream snapshots
        // can retain hasUnreadTurn after the desktop handles a separate read-state event.
        let receiptRows=(try? query(home+"/"+state,"SELECT thread_id, first_unread_turn IS NOT NULL, COALESCE(last_published_turn,'') FROM thread_read_receipts")) ?? []
        let receipts=Dictionary(receiptRows.map{($0[0],$0)},uniquingKeysWith:{_,b in b})
        let lookup = Dictionary(turns.map { ($0[0],$0) }, uniquingKeysWith: { a,b in b })
        let jobs:[Job] = threads.enumerated().compactMap { index,row in
            let t = lookup[row[0]]; var status = t?[2] ?? "unknown"
            // In-progress rows can survive a terminated Codex process. Never invent completion.
            if status == "inProgress", let stamp = Double(t?[3] ?? "0") {
                let seconds = stamp > 10_000_000_000 ? stamp/1000 : stamp
                if seconds>0 && Date().timeIntervalSince1970-seconds > 6*3600 { status="unknown" }
            }
            let receipt:Bool?=receipts[row[0]].flatMap{r in r[2] == t?[1] ? r[1] == "1" : nil}
            guard index<20 || t?[2]=="inProgress" || receipt==true || currentIDs.contains(row[0]) else{return nil}
            return Job(id:row[0],title:row[1].isEmpty ? L10n.text("제목 없는 대화") : row[1],project:URL(fileURLWithPath:row[2]).lastPathComponent,status:status,turn:t?[1] ?? "",readReceipt:receipt,startedAt:{let v=Double(t?[3] ?? "0") ?? 0;return v>10_000_000_000 ? v/1000:v}())
        }
        return Snapshot(jobs:jobs,warning:warning)
    }
}

@MainActor final class Monitor: ObservableObject {
    @Published var appLanguage=L10n.defaults.string(forKey:"appLanguage") ?? "system" {didSet{L10n.defaults.set(appLanguage,forKey:"appLanguage");displayAlerts.hideAll();updatePermission();onUpdate?()}}
    @Published var demoMode=false
    @Published var jobs=[Job](); @Published var error: String?; @Published var selected: String? = MotePreferences.store.string(forKey:"currentConversation"); @Published var all=false
    @Published var pinnedIDs:[String] = MotePreferences.store.stringArray(forKey:"workingConversations") ?? MotePreferences.store.string(forKey:"currentConversation").map{[$0]} ?? []
    @Published var notificationStatus=L10n.text("알림 권한 확인 중"); @Published var muted=false
    @Published var liveConnected=false
    @Published var showSettings=false
    @Published var undoPins:[String]?
    @Published var liveIssue:String?
    @Published var lastSync:Date?
    @Published var deferred=MotePreferences.store.dictionary(forKey:"deferredReplies") as? [String:String] ?? [:] {didSet{MotePreferences.store.set(deferred,forKey:"deferredReplies")}}
    @Published var privacyMode=MotePreferences.store.bool(forKey:"privacyMode") {didSet{MotePreferences.store.set(privacyMode,forKey:"privacyMode");displayAlerts.hideAll();UNUserNotificationCenter.current().removeAllDeliveredNotifications()}}
    @Published var thresholdAlerts=MotePreferences.store.object(forKey:"thresholdAlerts") as? Bool ?? true {didSet{MotePreferences.store.set(thresholdAlerts,forKey:"thresholdAlerts")}}
    @Published var awaySummaryEnabled=MotePreferences.store.object(forKey:"awaySummaryEnabled") as? Bool ?? true {didSet{MotePreferences.store.set(awaySummaryEnabled,forKey:"awaySummaryEnabled")}}
    @Published var shortcutChoice=MotePreferences.store.object(forKey:"shortcutChoice") as? Int ?? 1 {didSet{MotePreferences.store.set(shortcutChoice,forKey:"shortcutChoice");if !shortcut.register(shortcutChoice){settingsError=L10n.text("단축키 등록 실패 · 다른 조합을 선택해 주세요.")}}}
    let shortcut=GlobalShortcut()
    var thresholdPolicy=UsageThresholdPolicy(sent:Set(MotePreferences.store.stringArray(forKey:"thresholdSent") ?? []))
    var snoozed=[String:SnoozedNotice]()
    var awayNotices=[String:Job]()
    var isAway=false
    var screensAsleep=false
    func visibleTitle(_ job:Job)->String{privacyMode ? L10n.text("비공개 대화"):job.title}
    func snooze(_ ids:Set<String>,now:Date=Date()){
        for id in ids {if let job=jobs.first(where:{$0.id==id}){snoozed[id]=SnoozedNotice(jobs:[job],due:now.addingTimeInterval(600))}}
        displayAlerts.cancel(threads:ids)
    }
    func checkSnoozes(now:Date=Date()){
        for (id,notice) in snoozed {
            let pending=notice.unresolved(in:jobs)
            if pending.isEmpty{snoozed.removeValue(forKey:id);continue}
            guard notice.due<=now,!isAway,!paused,!muted else{continue}
            snoozed.removeValue(forKey:id)
            guard now.timeIntervalSince(notice.due)<600 else{continue}
            deliver(pending,title:L10n.text("모트 · 미뤄둔 작업을 확인해 주세요"),body:pending.map(visibleTitle).joined(separator:" · "),sound:attentionSound,identifier:"snooze:"+id)
        }
    }
    func setAway(_ away:Bool){
        guard isAway != away else{return};isAway=away
        if away {displayAlerts.hideAll();return}
        let pending=awayNotices.values.filter{old in jobs.contains{$0.id==old.id && $0.turn==old.turn && ["approval","answer","unread","failed"].contains($0.status)}}
        awayNotices=[:]
        if awaySummaryEnabled,!pending.isEmpty,!paused,!muted {
            let waiting=pending.filter{["approval","answer"].contains($0.status)}.count
            deliver(Array(pending),title:L10n.text("모트 · 자리 비운 사이 {0}건", [String(describing: pending.count)]),body:L10n.text("응답 대기 {0}건 · 답변·오류 {1}건", [String(describing: waiting), String(describing: pending.count-waiting)]),sound:false,identifier:"away-summary:"+UUID().uuidString)
        }
    }
    func openOldestWaiting(){
        if let job=jobs.filter({["approval","answer"].contains($0.status)}).min(by:{($0.waitSince ?? .distantFuture)<($1.waitSince ?? .distantFuture)}){open(job.id)}else{onOpenInbox?()}
    }
    @Published var showUsage=false
    @Published var usage:UsageSnapshot?
    @Published var usageLoading=false
    private var lastUsageRead=Date.distantPast
    func refreshUsage(force:Bool=false){
        guard !usageLoading,force || Date().timeIntervalSince(lastUsageRead)>60 else{return}
        usageLoading=true;lastUsageRead=Date()
        Task.detached{let snapshot=UsageSnapshot.read();await self.applyUsage(snapshot)}
    }
    @Published var shortResetAlerts=MotePreferences.store.object(forKey:"shortResetAlerts") as? Bool ?? true {didSet{MotePreferences.store.set(shortResetAlerts,forKey:"shortResetAlerts")}}
    @Published var weeklyResetAlerts=MotePreferences.store.object(forKey:"weeklyResetAlerts") as? Bool ?? true {didSet{MotePreferences.store.set(weeklyResetAlerts,forKey:"weeklyResetAlerts")}}
    @Published var reminderEnabled=MotePreferences.store.object(forKey:"reminderEnabled") as? Bool ?? true {didSet{MotePreferences.store.set(reminderEnabled,forKey:"reminderEnabled")}}
    @Published var reminderMinutes=MotePreferences.store.integer(forKey:"reminderMinutes")==0 ? 5:MotePreferences.store.integer(forKey:"reminderMinutes") {didSet{MotePreferences.store.set(reminderMinutes,forKey:"reminderMinutes")}}
    let connectivity=Connectivity()
    @Published var networkAvailable:Bool?
    func receiveNetwork(_ available:Bool){
        let previous=networkAvailable;networkAvailable=available
        if !available,previous != false,active>0,!muted,!paused {
            deliver([],title:L10n.text("모트 · 네트워크 연결 없음"),body:L10n.text("Codex 진행을 확인해 주세요. 연결 복구가 필요할 수 있어요."),sound:attentionSound,identifier:"network-offline")
        }
        if available,previous==false {refresh()}
        onUpdate?()
    }
    @Published var lastActivity=[String:Date]()
    func activityLabel(_ id:String,now:Date=Date())->String {
        if networkAvailable==false{return L10n.text("네트워크 연결 없음 · 진행 확인 필요")}
        guard liveConnected,let stamp=lastActivity[id] else{return L10n.text("활동 시각 확인 중")}
        let seconds=max(0,Int(now.timeIntervalSince(stamp)))
        return seconds>=300 ? L10n.text("마지막 변화 {0}분 전 · 오래 변화 없음", [String(describing: seconds/60)]):seconds>=60 ? L10n.text("마지막 활동 {0}분 전", [String(describing: seconds/60)]):L10n.text("마지막 활동 {0}초 전", [String(describing: seconds)])
    }
    func checkWaitReminders(now:Date=Date()){
        guard reminderEnabled,attentionAlerts,!muted,!paused,!isAway,liveConnected else{return}
        for job in jobs where ["approval","answer"].contains(job.status) && snoozed[job.id]==nil {
            guard let since=job.waitSince,now.timeIntervalSince(since)>=Double(reminderMinutes*60) else{continue}
            let state=liveStates[job.id]
            let key="reminder|"+NotificationLedger.key(thread:job.id,turn:job.turn,kind:job.status,requests:(state?.requestIDs ?? [])+(state?.asyncQuestionIDs ?? []))
            guard ledger.claim(key,now:now) else{continue}
            MotePreferences.store.set(ledger.sent,forKey:"notificationLedger")
            deliver([job],title:L10n.text("모트 · {0}분째 응답 대기", [String(describing: Int(now.timeIntervalSince(since)/60))]),body:job.title,sound:attentionSound,identifier:key)
        }
    }
    var resetPolicy=UsageResetPolicy(pending:MotePreferences.store.dictionary(forKey:"usageResetPending") as? [String:Double] ?? [:],delivered:Set(MotePreferences.store.stringArray(forKey:"usageResetDelivered") ?? []))
    func applyUsage(_ snapshot:UsageSnapshot?){
        usage=snapshot;usageLoading=false
        if let snapshot {resetPolicy.observe(snapshot,now:Date())}
        checkUsageResets()
        if let snapshot,thresholdAlerts,!muted,!paused,!isAway {
            for (minutes,threshold) in thresholdPolicy.observe(snapshot,now:Date()){
                deliver([],title:L10n.text("모트 · 한도가 얼마 남지 않았어요"),body:L10n.text("{0} 한도 {1}% 이하 · 로컬 기록 기준", [String(describing: minutes==10080 ? L10n.text("주간"):L10n.text("5시간")), String(describing: threshold)]),sound:attentionSound,identifier:"threshold:\(minutes):\(threshold)")
            }
            MotePreferences.store.set(Array(thresholdPolicy.sent),forKey:"thresholdSent")
        }
    }
    func checkUsageResets(){
        let due=resetPolicy.due(now:Date(),short:shortResetAlerts && !muted && !paused,weekly:weeklyResetAlerts && !muted && !paused)
        MotePreferences.store.set(resetPolicy.pending,forKey:"usageResetPending")
        MotePreferences.store.set(Array(resetPolicy.delivered),forKey:"usageResetDelivered")
        for minutes in due {
            deliver([],title:L10n.text("모트 · {0} 한도", [String(describing: minutes==300 ? L10n.text("5시간"):L10n.text("주간"))]),body:L10n.text("초기화 예정 시각이 됐어요 · 실제 잔여량은 Codex에서 확인해 주세요."),sound:completionSound,identifier:"quota-reset:\(minutes):\(Int(Date().timeIntervalSince1970))")
        }
    }
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
    var currentJobs:[Job] {let lookup=Dictionary(uniqueKeysWithValues:jobs.map{($0.id,$0)});return pinnedIDs.compactMap{lookup[$0]}.sorted{a,b in
        let aw=["approval","answer"].contains(a.status),bw=["approval","answer"].contains(b.status)
        if aw != bw{return aw};if aw,a.waitSince != b.waitSince{return (a.waitSince ?? .distantFuture)<(b.waitSince ?? .distantFuture)}
        return (pinnedIDs.firstIndex(of:a.id) ?? 0)<(pinnedIDs.firstIndex(of:b.id) ?? 0)
    }}
    var inboxJobs:[Job] {attentionJobs.filter{!pinnedIDs.contains($0.id)}}
    var otherRunning:[Job] {runningJobs.filter{!pinnedIDs.contains($0.id)}}
    func makeCurrent(_ id:String){selected=id;pinnedIDs=WorkingConversations.adding(id,to:pinnedIDs);MotePreferences.store.set(pinnedIDs,forKey:"workingConversations");MotePreferences.store.set(id,forKey:"currentConversation")}
    func removeCurrent(_ id:String){undoPins=pinnedIDs;pinnedIDs=WorkingConversations.removing(id,from:pinnedIDs);MotePreferences.store.set(pinnedIDs,forKey:"workingConversations")}
    func pause(){pauseUntil=Date().addingTimeInterval(1800);MotePreferences.store.set(pauseUntil,forKey:"pauseUntil")}
    func resume(){pauseUntil=nil;MotePreferences.store.removeObject(forKey:"pauseUntil")}
    func setLogin(_ enabled:Bool){do{if enabled{try SMAppService.mainApp.register()}else{try SMAppService.mainApp.unregister()};loginEnabled=SMAppService.mainApp.status == .enabled;settingsError=SMAppService.mainApp.status == .requiresApproval ? L10n.text("시스템 설정의 로그인 항목에서 허용해 주세요."):nil}catch{settingsError=L10n.text("자동 실행 설정 실패: {0}", [String(describing: error.localizedDescription)]);loginEnabled=SMAppService.mainApp.status == .enabled}}
    func dismissError(_ job:Job){dismissedErrors.append(job.id+job.turn);dismissedErrors=Array(dismissedErrors.suffix(500));MotePreferences.store.set(dismissedErrors,forKey:"dismissedErrors");reconcile();onUpdate?()}

    let mobile=MobileNotifier()
    let live=LiveObserver();var rawJobs=[Job]();var liveStates=[String:LiveState]();var waitSignatures=[String:String]()
    var waiting:Int {jobs.filter{["approval","answer"].contains($0.status)}.count}
    var unread:Int {jobs.filter{$0.status=="unread"}.count}
    var fairyStatus:String {waiting>0 ? (jobs.first{["approval","answer"].contains($0.status)}?.status ?? "answer") : unread>0 ? "unread" : jobs.contains{$0.status=="failed"} ? "failed" : active>0 ? "inProgress":"idle"}
    let monitoringStarted=Date().timeIntervalSince1970
    var baseline=false; var previous=[String:Job](); var timer: Timer?; var reading=false
    var onUpdate: (() -> Void)?
    let recordWatcher=RecordWatcher()
    var recordsDirty=true
    private var lastRecordRead=Date.distantPast
    private var lastWatchScan=Date.distantPast
    var active: Int { jobs.filter{$0.status=="inProgress"}.count }
    var chosen: Job? { jobs.first{$0.id==selected} ?? jobs.first }
    func start() {
        Task{
            if CommandLine.arguments.contains("--connect-mobile") {
                await mobile.connect()
                fputs(mobile.enabled ? "Mote mobile relay connected\n":"Mote mobile relay: \(mobile.issue ?? "unknown")\n",stderr)
            }else{await mobile.restore()}
        }
        shortcut.action={[weak self] in self?.openOldestWaiting()}
        if !shortcut.register(shortcutChoice){settingsError=L10n.text("단축키를 등록하지 못했어요. 설정에서 다른 조합을 선택해 주세요.")}
        displayAlerts.onSnooze={[weak self] ids in self?.snooze(ids)}
        DistributedNotificationCenter.default().addObserver(forName:NSNotification.Name("com.apple.screenIsLocked"),object:nil,queue:.main){[weak self] _ in Task{@MainActor in self?.screensAsleep=true;self?.setAway(true)}}
        DistributedNotificationCenter.default().addObserver(forName:NSNotification.Name("com.apple.screenIsUnlocked"),object:nil,queue:.main){[weak self] _ in Task{@MainActor in self?.screensAsleep=false;self?.refresh()}}
        for name in [NSWorkspace.screensDidSleepNotification,NSWorkspace.sessionDidResignActiveNotification]{NSWorkspace.shared.notificationCenter.addObserver(forName:name,object:nil,queue:.main){[weak self] _ in Task{@MainActor in self?.screensAsleep=true;self?.setAway(true)}}}
        for name in [NSWorkspace.screensDidWakeNotification,NSWorkspace.sessionDidBecomeActiveNotification]{NSWorkspace.shared.notificationCenter.addObserver(forName:name,object:nil,queue:.main){[weak self] _ in Task{@MainActor in self?.screensAsleep=false;self?.refresh()}}}
        connectivity.start{[weak self] available in Task{@MainActor in self?.receiveNetwork(available)}}
        live.onDiagnostic = {[weak self] message in Task{@MainActor in guard let self else{return};self.liveIssue=message;if message != nil{self.liveStates.removeAll();self.reconcile();self.onUpdate?()}}}
        live.onState = {[weak self] id,state in Task { @MainActor in self?.receive(id,state) }}
        live.onConnection = {[weak self] connected in Task { @MainActor in guard let self,self.liveConnected != connected else{return};self.liveConnected=connected;fputs("Mote IPC connected: \(connected)\n",stderr);if !connected{self.liveStates.removeAll();self.waitSignatures.removeAll();self.reconcile();self.onUpdate?()}}}
        recordWatcher.start{[weak self] in Task{@MainActor in self?.recordsDirty=true;self?.refresh(forceRead:false)}}
        live.start();refresh(); timer=Timer.scheduledTimer(withTimeInterval:3,repeats:true){[weak self] _ in Task { @MainActor in self?.refresh(forceRead:false) }};timer?.tolerance=0.3; updatePermission() }
    func updatePermission() { UNUserNotificationCenter.current().getNotificationSettings { settings in Task { @MainActor in self.notificationStatus = settings.authorizationStatus == .authorized ? L10n.text("알림 켜짐") : L10n.text("알림 허용 필요") } } }
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
        if !test,["completed","approval","answer"].contains(job.status),snoozed[job.id]==nil {
            Task{await mobile.send(thread:job.id,turn:job.turn,kind:job.status,title:job.title,privateMode:privacyMode)}
        }
        let content=UNMutableNotificationContent()
        content.title=test ? L10n.text("모트 · 테스트 알림") : ["approval":L10n.text("모트 · 승인이 필요해요"),"answer":L10n.text("모트 · 답변을 기다리고 있어요"),"failed":L10n.text("모트 · 작업에 문제가 생겼어요")][job.status] ?? L10n.text("모트 · 작업이 끝났어요")
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
        let title=pending.count==1 ? L10n.text("모트 · 작업이 끝났어요"):L10n.text("모트 · 작업 {0}개가 끝났어요", [String(describing: pending.count)])
        deliver(pending,title:title,body:pending.prefix(3).map(\.title).joined(separator:" · "),sound:completionSound,identifier:"complete:"+pending.map{$0.id+$0.turn}.sorted().joined(separator:":"))
    }
    func deliver(_ notices:[Job],title:String,body:String,sound:Bool,identifier:String){
        if isAway {for job in notices{awayNotices[job.id]=job};return}
        let originalCount=notices.count
        let notices=notices.filter{snoozed[$0.id]==nil}
        guard originalCount==0 || !notices.isEmpty else{return}
        let body=privacyMode && !notices.isEmpty ? L10n.text("대화 내용은 숨겨져 있어요. Mote에서 확인해 주세요."):body
        if let onNotice {onNotice(notices,title,body);return}
        let threads=Set(notices.map(\.id));alertThreads[identifier]=threads
        if alertDisplay != "system" {
            displayAlerts.show(title:title,body:body,mode:alertDisplay,sound:sound,threads:threads){[weak self] in
                guard let self else{return};if notices.count==1,let job=notices.first,job.id != "test"{self.open(job.id)}else{self.onOpenInbox?()}
            };return
        }
        let content=UNMutableNotificationContent();content.title=title;content.body=body
        if !notices.isEmpty{content.categoryIdentifier="MOTE_TASK"}
        if sound{content.sound = .default};content.userInfo=["threadID":notices.count==1 ? notices[0].id:"batch","threadIDs":Array(threads)]
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier:identifier,content:content,trigger:nil)){error in
            if error != nil{Task{@MainActor in self.settingsError=L10n.text("알림 전송에 실패했어요. 알림 허용 설정을 확인해 주세요.")}}
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
    func refresh(forceRead:Bool=true) {
        updates.checkIfNeeded()
        if !demoMode,screensAsleep || CGEventSource.secondsSinceLastEventType(.combinedSessionState,eventType:CGEventType(rawValue:UInt32.max)!)>300 {setAway(true)}
        checkSnoozes()
        checkUsageResets()
        checkWaitReminders()
        refreshUsage()
        if Date().timeIntervalSince(lastWatchScan)>30 {lastWatchScan=Date();recordWatcher.rescanEventually();Task{await mobile.flush()}}
        // Keep housekeeping responsive without reopening every database every 3s.
        guard forceRead || recordsDirty || Date().timeIntervalSince(lastRecordRead)>30 else{return}
        // A token stream can write the WAL continuously. Never turn filesystem
        // events into more full queries than the previous 3-second fallback.
        guard forceRead || Date().timeIntervalSince(lastRecordRead)>=3 else{return}
        guard !reading else{return}; reading=true;recordsDirty=false;lastRecordRead=Date()
        let currentIDs=Set(pinnedIDs)
        Task.detached {
            do {let snapshot=try LocalReader.snapshot(currentIDs:currentIDs);await self.apply(.success(snapshot.jobs),warning:snapshot.warning)}
            catch {await self.apply(.failure(error))}
        }
    }
    func apply(_ result:Result<[Job],Error>,warning:String?=nil) {
        reading=false
        switch result {case .success(let found):
            if baseline {for j in found where previous[j.id]?.turn != j.turn && j.startedAt>=monitoringStarted-3 {makeCurrent(j.id)}}
            if baseline { for j in found { if let old=previous[j.id], ["completed","failed"].contains(j.status), (j.turn != old.turn || old.status == "inProgress") { notify(j) } } }
            previous=Dictionary(uniqueKeysWithValues:found.map{($0.id,$0)});rawJobs=found;lastSync=Date()
            if !baseline {for job in found.reversed() where job.status=="inProgress" && !pinnedIDs.contains(job.id){makeCurrent(job.id)}}
            let chronological=found.sorted{a,b in a.startedAt==b.startedAt ? a.turn<b.turn:a.startedAt<b.startedAt}
            if currentPolicy.started==0 {if let newest=chronological.last{followNewTurn(id:newest.id,turn:newest.turn,started:newest.startedAt)}}
            else{for job in chronological{followNewTurn(id:job.id,turn:job.turn,started:job.startedAt)}}
            live.observe(found.map(\.id));reconcile();if error != warning {error=warning};baseline=true
            if isAway,!screensAsleep,CGEventSource.secondsSinceLastEventType(.combinedSessionState,eventType:CGEventType(rawValue:UInt32.max)!)<300 {setAway(false)}
        case .failure(let e): recordsDirty=true;error=e.localizedDescription }
        onUpdate?()
    }
    func receive(_ id:String,_ state:LiveState) {
        let old=liveStates[id]
        if let latest=state.latestTurn,let raw=rawJobs.first(where:{$0.id==id}),latest.id != raw.turn,latest.started/1000 < raw.startedAt {return}
        if lastActivity[id]==nil || (old != nil && (old!.activityRevision != state.activityRevision || old!.latestTurn?.id != state.latestTurn?.id || old!.waiting != state.waiting)) {if Date().timeIntervalSince(lastActivity[id] ?? .distantPast)>=1 {lastActivity[id]=Date()}}
        if let latest=state.latestTurn,rawJobs.contains(where:{$0.id==id}){followNewTurn(id:id,turn:latest.id,started:latest.started/1000)}
        if let latest=state.latestTurn,["completed","failed"].contains(latest.status),let prior=old?.latestTurn,
            latest.id != prior.id || latest.status != prior.status,let raw=rawJobs.first(where:{$0.id==id}) {
            var finished=raw;finished.turn=latest.id;finished.status=latest.status;finished.readReceipt = raw.turn == latest.id ? raw.readReceipt:nil;notify(finished)
            refresh()
        }
        if liveStates[id]?.waiting != state.waiting {fputs("Mote waiting state: \(state.waiting ?? "none")\n",stderr)}
        liveStates[id]=state
        if let kind=state.waiting,let raw=rawJobs.first(where:{$0.id==id}) {
            let signature=(state.latestTurn?.id ?? raw.turn)+kind+(state.requestIDs+state.asyncQuestionIDs).sorted().joined(separator:":")
            if waitSignatures[id] != signature {if waitSignatures[id] != nil{snoozed.removeValue(forKey:id)};var job=raw;job.turn=state.latestTurn?.id ?? raw.turn;job.status=kind;job.reason=state.requestReasons.values.sorted().first ?? (!state.asyncQuestionIDs.isEmpty ? L10n.text("질문에 답변이 필요해요"):nil);notify(job,requests:state.requestIDs+state.asyncQuestionIDs);waitSignatures[id]=signature}
        }else{waitSignatures.removeValue(forKey:id)}
        reconcile();onUpdate?()
    }
    func reconcile(){
        let oldWaitTimes=waitTimes
        let reconciled=rawJobs.map {raw in
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
                    if let kind=liveState.waiting {job.status=kind;job.reason=liveState.requestReasons.values.sorted().first ?? (!liveState.asyncQuestionIDs.isEmpty ? L10n.text("질문에 답변이 필요해요"):nil)}
                    else if liveState.runtime["type"] as? String == "active",latest == nil || latest?.status == "inProgress" {job.status="inProgress"}
                    if job.status=="completed",(job.readReceipt ?? liveState.unread)==true {job.status="unread"}
                }
            }
            if job.status=="completed",job.readReceipt==true{job.status="unread"}
            if job.status=="unread",PresentationPolicy.isDeferred(thread:job.id,turn:job.turn,records:deferred){job.status="deferred"}
            if ["approval","answer"].contains(job.status){
                let state=liveStates[raw.id]
                let key=NotificationLedger.key(thread:raw.id,turn:state?.latestTurn?.id ?? raw.turn,kind:job.status,requests:(state?.requestIDs ?? [])+(state?.asyncQuestionIDs ?? []))
                if waitTimes[key]==nil{waitTimes[key]=Date()};job.waitSince=waitTimes[key]
            }
            if job.status=="failed",dismissedErrors.contains(job.id+job.turn){job.status="reviewedError"}
            return job
        }.enumerated().sorted{a,b in
            func rank(_ status:String)->Int{switch status{case "approval","answer":return 0;case "failed":return 1;case "unread":return 2;case "inProgress":return 3;default:return 4}}
            let ar=rank(a.element.status),br=rank(b.element.status)
            if ar==0 && br==0,a.element.waitSince != b.element.waitSince{return (a.element.waitSince ?? .distantFuture)<(b.element.waitSince ?? .distantFuture)}
            return ar==br ? a.offset<b.offset:ar<br
        }.map(\.element)
        if jobs != reconciled {jobs=reconciled}
        if waitTimes.count>500 {waitTimes=Dictionary(uniqueKeysWithValues:waitTimes.sorted{$0.value>$1.value}.prefix(300).map{($0.key,$0.value)})}
        if waitTimes != oldWaitTimes {MotePreferences.store.set(waitTimes,forKey:"waitTimes")}
        clearResolvedAlerts()
    }
    var openURL:(URL)->Bool = {NSWorkspace.shared.open($0)}
    static func conversationURL(_ id:String)->URL? {
        guard !id.isEmpty,id.unicodeScalars.allSatisfy({CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_"}) else{return nil}
        var parts=URLComponents();parts.scheme="codex";parts.host="threads";parts.path="/"+id
        parts.queryItems=[URLQueryItem(name:"hostId",value:"local")]
        return parts.url
    }
    func open(_ id:String) {
        if demoMode{return}
        guard let url=Self.conversationURL(id) else{error=L10n.text("대화 링크가 올바르지 않아요.");onUpdate?();return}
        if openURL(url){makeCurrent(id);refresh()}else{error=L10n.text("Codex에서 대화를 열지 못했어요. Codex 설치와 실행 상태를 확인해 주세요.");onUpdate?()}
        // Opening a link is not proof that a reply was read; only Codex receipts clear it.
    }

}

struct Dust: View {
    var status:String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body:some View{
        TimelineView(.periodic(from:.now,by:reduceMotion ? 3600:0.2)){context in
            let frame=reduceMotion ? 0:Int(context.date.timeIntervalSince1970*5)%4
            Image(nsImage:MenuFairy.portrait(state:status,frame:frame)).resizable().interpolation(.high).scaledToFit()
        }.accessibilityLabel(["approval":L10n.text("승인을 기다리는 요정"),"answer":L10n.text("답변을 기다리는 요정"),"unread":L10n.text("새 답변을 배달하는 요정"),"failed":L10n.text("오류를 알리는 요정"),"inProgress":L10n.text("작업 중인 요정")][status] ?? L10n.text("쉬는 요정"))
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
final class MotePanel: NSPanel {
    override var canBecomeKey:Bool { true }
    // The panel is rebuilt on open. Release hidden SwiftUI timelines rather than
    // leaving animations/layout subscribed while only the menu bar is visible.
    override func orderOut(_ sender:Any?) { super.orderOut(sender); contentView=nil }
    override func cancelOperation(_ sender:Any?) { orderOut(nil) }
}
struct RunningIndicator:View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body:some View {
        TimelineView(.periodic(from:.now,by:reduceMotion ? 3600:0.2)){context in
            let phase=reduceMotion ? 0:context.date.timeIntervalSince1970
            ZStack {
                Circle().stroke(Palette.olive.opacity(0.14),lineWidth:2)
                Circle().trim(from:0,to:0.28).stroke(Palette.olive,style:StrokeStyle(lineWidth:2,lineCap:.round))
                    .rotationEffect(.degrees(reduceMotion ? -90:phase*130))
            }.frame(width:17,height:17)
        }.accessibilityLabel(L10n.text("작업 진행 중"))
    }
}
struct RunningCaption:View {
    var project:String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body:some View {
        TimelineView(.periodic(from:.now,by:reduceMotion ? 3600:0.33)){context in
            let step=Int(context.date.timeIntervalSince1970*3)%3
            HStack(spacing:5){Text(L10n.text("{0} · 작업 중", [String(describing: project)]));HStack(spacing:3){ForEach(0..<3){i in
                Circle().fill(Palette.olive.opacity(reduceMotion || i==step ? 0.85:0.20)).frame(width:3,height:3)
            }}.accessibilityHidden(true)}.font(.caption).foregroundStyle(.secondary)
        }
    }
}
struct UpdateNotice:View {
    @ObservedObject var updates:UpdateChecker
    var body:some View {
        if updates.available,let release=updates.release {
            HStack{Text(L10n.text("새 버전 {0}",[release.version])).font(.caption);Spacer();Button(L10n.text("앱에서 업데이트")){updates.installUpdate()};Button(L10n.text("변경 내용")){updates.openNotes()}}.font(.caption).padding(10).background(Palette.olive.opacity(0.08),in:RoundedRectangle(cornerRadius:9))
        }
    }
}
struct Panel:View {
    @ObservedObject var model:Monitor
    var headline:String {
        if model.networkAvailable==false{return L10n.text("네트워크 연결을\n확인해 주세요.")}
        if model.waiting>0 {
            let approvals=model.jobs.filter{$0.status=="approval"}.count
            let kind=approvals==model.waiting ? L10n.text("승인을"):approvals==0 ? L10n.text("답변을"):L10n.text("응답을")
            return L10n.text("{0}개 작업이\n{1} 기다려요.", [String(describing: model.waiting), String(describing: kind)])
        }
        if model.unread>0{return L10n.text("미확인 답변이\n{0}개 있어요.", [String(describing: model.unread)])}
        if model.jobs.contains(where:{$0.status=="failed"}){return L10n.text("확인이 필요한\n오류가 있어요.")}
        if model.error != nil && model.active==0{return L10n.text("작업 상태를 확인할 수 없어요.")}
        return model.active>0 ? L10n.text("{0}개 작업이\n진행 중이에요.", [String(describing: model.active)]):L10n.text("지금은 쉬고 있어요.")
    }
    var body:some View {
        VStack(alignment:.leading,spacing:16){
            HStack{Text("mote.").font(.system(size:24,weight:.semibold,design:.rounded));HStack(spacing:4){Circle().fill((model.error != nil || model.networkAvailable==false) ? Color.orange:model.liveConnected ? Palette.olive:Color.orange).frame(width:6,height:6);Text(model.error != nil ? L10n.text("기록 확인 필요"):model.networkAvailable==false ? L10n.text("네트워크 없음"):model.liveIssue != nil ? L10n.text("기록 감지"):model.liveConnected ? L10n.text("연결됨"):L10n.text("재연결 중")).font(.system(size:11))}.accessibilityElement(children:.combine);Spacer();Button{model.showSettings.toggle()}label:{Image(systemName:"slider.horizontal.3")}.buttonStyle(.plain).accessibilityLabel(L10n.text("설정"))}
            UpdateNotice(updates:model.updates)
            if model.demoMode{Text(L10n.text("미리보기 · 실제 대화와 무관한 테스트 상태")).font(.caption).foregroundStyle(.orange)}
            if model.showSettings{settings}else{
                HStack{VStack(alignment:.leading,spacing:7){Text(L10n.text("작은 먼지가 챙겨둘게요")).font(.caption).foregroundStyle(.secondary);Text(headline).font(.system(size:25,weight:.semibold)).fixedSize(horizontal:false,vertical:true)
                    if model.waiting>0{Text(L10n.text("승인 {0} · 답변 {1} · 오래 기다린 순", [String(describing: model.jobs.filter{$0.status=="approval"}.count), String(describing: model.jobs.filter{$0.status=="answer"}.count)])).font(.system(size:11)).foregroundStyle(.secondary)}
                };Spacer();Dust(status:model.networkAvailable==false ? "offline":model.fairyStatus).frame(width:100,height:95)}
                if !model.currentJobs.isEmpty {
                    HStack{Label(L10n.text("고정한 대화 {0}", [String(describing: model.currentJobs.count)]),systemImage:"pin.fill").font(.system(size:12,weight:.semibold)).foregroundStyle(.primary);Spacer();Button(L10n.text("완료 정리")){model.cleanCompleted()}.font(.system(size:11)).buttonStyle(.borderless)}
                    VStack(spacing:5){ForEach(model.currentJobs){current in
                        HStack(spacing:5){row(current);if !["approval","answer"].contains(current.status){Button{model.removeCurrent(current.id)}label:{Image(systemName:"xmark").font(.system(size:10)).frame(width:25,height:32)}.buttonStyle(.plain).foregroundStyle(.secondary).help(L10n.text("고정 해제 · 대화는 삭제하지 않아요"))}}
                    }}
                }
                HStack{Button((model.error != nil || model.networkAvailable==false) ? L10n.text("상태 확인 불가"):L10n.text("확인할 작업 {0}", [String(describing: model.attentionJobs.count)])){model.all=false}.fontWeight(model.all ? .regular:.semibold).foregroundStyle(model.all ? Color.secondary:Palette.olive);Button(L10n.text("감지한 대화 {0}", [String(describing: model.jobs.count)])){model.all=true}.fontWeight(model.all ? .semibold:.regular).foregroundStyle(model.all ? Color.primary:Color.secondary);Spacer()}.buttonStyle(.borderless)
                VStack(alignment:.leading,spacing:4){
                    if model.all{ForEach(model.jobs.filter{!model.pinnedIDs.contains($0.id)}){row($0)}}else{
                        ForEach(model.inboxJobs){row($0)}
                        if !model.otherRunning.isEmpty{Text(L10n.text("진행 중 {0}", [String(describing: model.active)])).font(.caption).foregroundStyle(.secondary).padding(.top,15);ForEach(model.otherRunning){row($0)}}

                    }
                }
            }
            if !model.showSettings {
                DisclosureGroup(isExpanded:$model.showUsage){UsageDashboard(model:model).padding(.top,8)}label:{
                    HStack(spacing:6){Image(systemName:"chart.bar");Text(L10n.text("사용량"));Spacer();
                        if let snapshot=model.usage,let window=snapshot.windows.first,!window.expired(Date()),Date().timeIntervalSince(snapshot.recorded)<=900 {
                            Text(L10n.text("{0} · {1}% 남음", [String(describing: window.title), String(describing: window.remaining)])).monospacedDigit()
                        }else{Text(model.usageLoading ? L10n.text("사용량 확인 중…"):model.usage == nil ? L10n.text("사용량 기록 없음"):L10n.text("최근 기록 보기"))}
                    }.font(.system(size:11)).foregroundStyle(.secondary)
                }.padding(.top,8)
            }
            if model.undoPins != nil{HStack{Text(L10n.text("작업 목록을 정리했어요"));Spacer();Button(L10n.text("되돌리기")){model.undoCleanup()}}.font(.caption).foregroundStyle(.secondary)}
            if let issue=model.liveIssue{Text(issue).font(.caption).foregroundStyle(.orange)}
            if let error=model.error{Text(error).font(.caption).foregroundStyle(.orange)}
            if let message=model.settingsError{Text(message).font(.caption).foregroundStyle(.secondary)}
            Divider()
            if model.notificationStatus==L10n.text("알림 허용 필요") {
                HStack{Label(L10n.text("macOS 알림이 허용되지 않았어요"),systemImage:"exclamationmark.triangle").foregroundStyle(.orange);Spacer();Button(L10n.text("설정 열기")){model.requestNotifications()}}.font(.system(size:12,weight:.medium))
            }
            HStack{Button(model.notificationStatus){model.requestNotifications()};Spacer();Menu{Button(L10n.text("새로고침")){model.refresh()};Button(model.paused ? L10n.text("알림 다시 켜기"):L10n.text("30분 동안 알림 쉬기")){if model.paused{model.resume()}else{model.pause()}};Button(L10n.text("테스트 알림")){model.notify(Job(id:"test",title:L10n.text("모트 알림이 정상 작동해요"),project:"",status:"completed",turn:UUID().uuidString),test:true)};Button(L10n.text("종료")){NSApp.terminate(nil)}}label:{Image(systemName:"ellipsis").frame(width:30,height:28).accessibilityLabel(L10n.text("더 보기"))}}.font(.system(size:12,weight:.medium)).foregroundStyle(.primary).buttonStyle(.borderless)
            if model.paused,let until=model.pauseUntil{HStack{Text(L10n.text("알림 쉬는 중 · {0}까지", [String(describing: until.moteFormatted(date:.omitted,time:.shortened))]));Spacer();Button(L10n.text("다시 켜기")){model.resume()}}.font(.caption).foregroundStyle(.secondary)}
        }.padding(23).frame(width:440).tint(Palette.olive).environment(\.locale,L10n.locale).disabled(model.demoMode)
    }
    func stateColor(_ status:String)->Color {
        switch status {case "approval":return Color(nsColor:NSColor(name:nil){$0.bestMatch(from:[.darkAqua,.aqua]) == .darkAqua ? NSColor.systemOrange:NSColor(calibratedRed:0.64,green:0.29,blue:0.02,alpha:1)});case "answer":return Color(nsColor:NSColor(name:nil){$0.bestMatch(from:[.darkAqua,.aqua]) == .darkAqua ? NSColor.systemTeal:NSColor(calibratedRed:0.10,green:0.36,blue:0.41,alpha:1)});case "failed":return .red;default:return Palette.olive}
    }
    func row(_ job:Job)->some View {
        Button{model.open(job.id)}label:{
            HStack(spacing:11){Group{if job.status=="inProgress"{RunningIndicator()}else{Image(systemName:job.symbol)}}.frame(width:32,height:32).foregroundStyle(stateColor(job.status)).background(stateColor(job.status).opacity(0.12),in:RoundedRectangle(cornerRadius:9))
                VStack(alignment:.leading,spacing:4){Text(model.visibleTitle(job)).font(.system(size:14,weight:.medium)).lineLimit(1);if job.status=="inProgress"{RunningCaption(project:model.privacyMode ? L10n.text("비공개"):job.project);TimelineView(.periodic(from:.now,by:5)){context in Text(model.activityLabel(job.id,now:context.date)).font(.system(size:10)).foregroundStyle(.secondary)}}else if ["approval","answer"].contains(job.status){Text(model.privacyMode ? job.label:"\(job.project) · \(L10n.text(job.reason ?? job.label))").font(.caption).foregroundStyle(stateColor(job.status)).fixedSize(horizontal:false,vertical:true)}else{Text(model.privacyMode ? job.label:"\(job.project) · \(job.label)").font(.caption).foregroundStyle(.secondary)}
                    if ["approval","answer"].contains(job.status){if let since=job.waitSince{TimelineView(.periodic(from:.now,by:30)){context in Text(L10n.text("기다린 지 {0}분 · 감지 시점 기준", [String(describing: max(0,Int(context.date.timeIntervalSince(since)/60)))])).font(.system(size:11)).foregroundStyle(.secondary)}}else{Text(L10n.text("대기 시간 확인 중")).font(.system(size:11)).foregroundStyle(.secondary)}}
                };Spacer();if job.status=="unread"{Circle().fill(Palette.olive).frame(width:7,height:7)};if ["approval","answer"].contains(job.status){Label(L10n.text("열기"),systemImage:"arrow.up.right").font(.system(size:12,weight:.semibold)).foregroundStyle(stateColor(job.status))}else{Label(L10n.text("열기"),systemImage:"arrow.up.right").font(.system(size:11)).foregroundStyle(.secondary)}
            }.padding(11).frame(maxWidth:.infinity,alignment:.leading).background(Color.primary.opacity(0.035),in:RoundedRectangle(cornerRadius:11))
        }.buttonStyle(.plain).help(L10n.text("Codex에서 대화 열기")).contextMenu{Button(L10n.text("대화 고정")){model.makeCurrent(job.id)};
            if job.status=="unread"{Button(L10n.text("답변 나중에 보기")){model.deferReply(job)}}
            if job.status=="deferred"{Button(L10n.text("미확인 답변으로 다시 표시")){model.restoreReply(job)}};if job.status=="failed"{Button(L10n.text("오류 확인했어요")){model.dismissError(job)}}}
    }
    var settings:some View {
        VStack(alignment:.leading,spacing:16){
            Picker("Language / 언어",selection:$model.appLanguage){Text("System / 시스템").tag("system");Text("한국어").tag("ko");Text("English").tag("en")}
            Text(L10n.text("알림과 실행")).font(.title3.weight(.semibold))
            Picker(L10n.text("알림 표시 화면"),selection:$model.alertDisplay){Text(L10n.text("마우스가 있는 화면")).tag("cursor");Text(L10n.text("주 모니터")).tag("main");Text(L10n.text("macOS 기본 알림")).tag("system");ForEach(NSScreen.screens,id:\.self){screen in
                Text(screen.localizedName).tag("display:"+((screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.stringValue ?? ""))
            }}
            Text(model.alertDisplay == "system" ? L10n.text("macOS 알림 설정과 집중 모드를 따릅니다."):L10n.text("모트 알림은 집중 모드와 별도로 표시돼요. 입력 중인 창의 포커스는 유지돼요.")).font(.caption).foregroundStyle(.secondary)
            Button(L10n.text("이 화면 설정으로 테스트 알림")){model.notify(Job(id:"test",title:L10n.text("모트가 작업 화면으로 찾아왔어요"),project:"",status:"completed",turn:UUID().uuidString),test:true)}
            Toggle(L10n.text("개인정보 모드 · 제목과 프로젝트 숨기기"),isOn:$model.privacyMode)
            Toggle(L10n.text("자리 비움 후 요약"),isOn:$model.awaySummaryEnabled)
            Picker(L10n.text("가장 오래 기다린 대화 열기"),selection:$model.shortcutChoice){Text(L10n.text("사용 안 함")).tag(0);Text("⌃⌥Space").tag(1);Text("⌘⇧Space").tag(2)}
            Toggle(L10n.text("사용량 20%·5% 임계 알림"),isOn:$model.thresholdAlerts)
            Toggle(L10n.text("로그인 시 모트 실행"),isOn:Binding(get:{model.loginEnabled},set:{model.setLogin($0)}))
            Divider()
            Toggle(L10n.text("승인·질문 알림"),isOn:$model.attentionAlerts)
            Toggle(L10n.text("승인·질문 알림 소리"),isOn:$model.attentionSound)
            Toggle(L10n.text("승인·질문 대기 재알림"),isOn:$model.reminderEnabled)
            if model.reminderEnabled {Picker(L10n.text("재알림 간격"),selection:$model.reminderMinutes){Text(L10n.text("3분 후")).tag(3);Text(L10n.text("5분 후")).tag(5);Text(L10n.text("10분 후")).tag(10)}}
            Text(L10n.text("처리되지 않은 같은 요청에 한 번만 다시 알려줘요. 오래 변화 없음 표시는 멈춤 판정이 아닙니다.")).font(.system(size:10)).foregroundStyle(.secondary)
            Toggle(L10n.text("작업 완료 알림"),isOn:$model.completionAlerts)
            Toggle(L10n.text("완료·오류 알림 소리"),isOn:$model.completionSound)
            Toggle(L10n.text("오류 알림"),isOn:$model.errorAlerts)
            Toggle(L10n.text("5시간 한도 초기화 시각 알림"),isOn:$model.shortResetAlerts)
            Toggle(L10n.text("주간 한도 초기화 시각 알림"),isOn:$model.weeklyResetAlerts)
            Text(L10n.text("모트 실행 중, 미리 확인한 초기화 시각에 한 번 알려줘요. 실제 한도 갱신을 보장하지 않으며 10분 이상 지난 알림은 생략해요.")).font(.system(size:10)).foregroundStyle(.secondary)
            Button(model.paused ? L10n.text("알림 다시 켜기"):L10n.text("30분 동안 알림 쉬기")){if model.paused{model.resume()}else{model.pause()}}
            Text(L10n.text("작업 상태는 알림을 쉬는 동안에도 계속 표시돼요.")).font(.caption).foregroundStyle(.secondary)
            Text(L10n.text("자동 실행은 앱을 고정된 위치에 두고 설정하세요.")).font(.caption).foregroundStyle(.secondary)
            Divider()
            DiagnosticsView(model:model,updates:model.updates)
        }.toggleStyle(.switch).padding(.vertical,8)
    }
}
private struct PanelHeightKey:PreferenceKey {
    static let defaultValue:CGFloat=0
    static func reduce(value:inout CGFloat,nextValue:()->CGFloat){value=max(value,nextValue())}
}
struct CompactPanel:View {
    @ObservedObject var model:Monitor
    let width:CGFloat;let limit:CGFloat;var resize:(CGFloat)->Void
    @State private var contentHeight:CGFloat=360
    var body:some View {
        ScrollView{Panel(model:model).background(GeometryReader{geo in Color.clear.preference(key:PanelHeightKey.self,value:geo.size.height)})}
            .frame(width:width,height:min(limit,max(240,contentHeight)))
            .background(Glass()).clipShape(RoundedRectangle(cornerRadius:20))
            .onPreferenceChange(PanelHeightKey.self){height in
                guard height>0 else{return};contentHeight=height;resize(min(limit,max(240,height)))
            }
    }
}
@MainActor final class AppDelegate:NSObject,NSApplicationDelegate,UNUserNotificationCenterDelegate {
    var outsideClickMonitor:Any?;var localClickMonitor:Any?
    var didSetup=false;let monitor=Monitor();var item:NSStatusItem!;var panel:MotePanel!;var menuFairy:MenuFairy!
    func applicationDidFinishLaunching(_ notification:Notification){
        guard !didSetup else{return};didSetup=true
        fputs("Mote startup\n",stderr);NSApp.setActivationPolicy(.accessory);UNUserNotificationCenter.current().delegate=self
        let snoozeAction=UNNotificationAction(identifier:"MOTE_SNOOZE",title:L10n.text("10분 뒤 다시"),options:[])
        UNUserNotificationCenter.current().setNotificationCategories([UNNotificationCategory(identifier:"MOTE_TASK",actions:[snoozeAction],intentIdentifiers:[],options:[])])
        item=NSStatusBar.system.statusItem(withLength:NSStatusItem.variableLength)
        item.button?.target=self;item.button?.action=#selector(toggle)
        menuFairy=MenuFairy(button:item.button);menuFairy.update("idle")
        panel=MotePanel(contentRect:NSRect(x:0,y:0,width:440,height:700),styleMask:[.titled,.fullSizeContentView],backing:.buffered,defer:false)
        panel.title="Mote";panel.titleVisibility = .hidden;panel.titlebarAppearsTransparent=true
        panel.isOpaque=false;panel.backgroundColor = .clear;panel.hasShadow=true;panel.level = .floating
        panel.isMovableByWindowBackground=true;panel.hidesOnDeactivate=false
        panel.standardWindowButton(.closeButton)?.isHidden=true;panel.standardWindowButton(.miniaturizeButton)?.isHidden=true;panel.standardWindowButton(.zoomButton)?.isHidden=true
        monitor.onUpdate = {[weak self] in guard let self else{return};self.menuFairy.update(self.monitor.fairyStatus);let title=self.monitor.error != nil ? L10n.text(" 확인 필요") : " "+self.monitor.menuSummary;if self.item.button?.title != title {self.item.button?.title=title}}
        monitor.onOpenInbox = {[weak self] in guard let self else{return};if !self.panel.isVisible{self.toggle()}}
        outsideClickMonitor=NSEvent.addGlobalMonitorForEvents(matching:[.leftMouseDown,.rightMouseDown]){[weak self] _ in Task{@MainActor in self?.panel.orderOut(nil)}}
        localClickMonitor=NSEvent.addLocalMonitorForEvents(matching:[.leftMouseDown,.rightMouseDown]){[weak self] event in
            MainActor.assumeIsolated {
                if let self,self.panel.isVisible,event.window !== self.panel,event.window !== self.item.button?.window,event.window != nil,self.panel.frame.contains(NSEvent.mouseLocation)==false {self.panel.orderOut(nil)}
            };return event
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName:NSWorkspace.didActivateApplicationNotification,object:nil,queue:.main){[weak self] note in
            guard let app=note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,app.processIdentifier != ProcessInfo.processInfo.processIdentifier else{return}
            Task{@MainActor in self?.panel.orderOut(nil)}
        }
        if CommandLine.arguments.contains("--demo"){startDemo()}else{monitor.start()};if !CommandLine.arguments.contains("--background"){toggle()};fputs("Mote panel ready\n",stderr)
    }
    func startDemo(){
        monitor.demoMode=true
        let pins=monitor.pinnedIDs
        Task{@MainActor in
            let states=["inProgress","approval","answer","unread","offline","idle"]
            for state in states {
                self.monitor.networkAvailable=state != "offline";self.monitor.liveConnected=true
                self.monitor.notificationStatus=L10n.text("테스트 알림")
                let status=state=="offline" ? "inProgress":state=="idle" ? "completed":state
                let job=Job(id:"demo",title:L10n.text("[데모] 로그인 화면 구현"),project:"mote-demo",status:status,turn:"demo",waitSince:["approval","answer"].contains(state) ? Date().addingTimeInterval(-300):nil,reason:state=="approval" ? L10n.text("명령 실행 승인이 필요해요"):state=="answer" ? L10n.text("진행 방식을 선택해 주세요"):nil)
                self.monitor.jobs=[job];self.monitor.pinnedIDs=[job.id];self.monitor.lastActivity[job.id]=Date()
                self.monitor.onUpdate?()
                if !self.panel.isVisible{self.toggle()}
                if ["approval","answer","unread","offline"].contains(state) {
                    self.monitor.displayAlerts.show(title:["approval":L10n.text("[데모] 모트 · 승인이 필요해요"),"answer":L10n.text("[데모] 모트 · 답변을 기다려요"),"unread":L10n.text("[데모] 모트 · 답변이 도착했어요"),"offline":L10n.text("[데모] 모트 · 네트워크 연결 없음")][state]!,body:job.title,mode:self.monitor.alertDisplay=="system" ? "cursor":self.monitor.alertDisplay,sound:false,threads:["demo"],open:{})
                }
                try? await Task.sleep(nanoseconds:8_000_000_000)
            }
            self.monitor.displayAlerts.cancel(threads:["demo"])
            self.monitor.pinnedIDs=pins;self.monitor.jobs=[];self.monitor.demoMode=false
            self.monitor.networkAvailable=nil;self.monitor.start()
            self.monitor.onUpdate?()
        }
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
        panel.contentView=NSHostingView(rootView:CompactPanel(model:monitor,width:width,limit:height){[weak self] fitted in
            guard let self,abs(self.panel.frame.height-fitted)>1 else{return}
            self.panel.setFrame(NSRect(x:x,y:top-fitted,width:width,height:fitted),display:true)
        })
        panel.setFrame(NSRect(x:x,y:top-height,width:width,height:height),display:true)
        panel.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
    }
    nonisolated func userNotificationCenter(_ center:UNUserNotificationCenter,willPresent notification:UNNotification,withCompletionHandler completion:@escaping(UNNotificationPresentationOptions)->Void){completion([.banner,.sound])}
    nonisolated func userNotificationCenter(_ center:UNUserNotificationCenter,didReceive response:UNNotificationResponse,withCompletionHandler completion:@escaping()->Void){let id=response.notification.request.content.userInfo["threadID"] as? String;Task{@MainActor in if response.actionIdentifier=="MOTE_SNOOZE"{let ids=Set(response.notification.request.content.userInfo["threadIDs"] as? [String] ?? id.map{[$0]} ?? []);self.monitor.snooze(ids)}else if id=="batch"{self.monitor.onOpenInbox?()}else if let id,id != "test"{self.monitor.open(id)}};completion()}
}
if CommandLine.arguments.contains("--schema") {print(LocalReader.diagnosticSummary())}else if CommandLine.arguments.contains("--diagnose") {do {let jobs=try LocalReader.read();for job in jobs {if CommandLine.arguments.contains("--titles"){print(job.title)};print("\(job.id) \(job.status) unread=\(job.readReceipt.map{String($0)} ?? "unknown")")};print("Detected \(jobs.count) local tasks")}catch{fputs("\(error)\n",stderr);exit(1)}}else{MainActor.assumeIsolated {let lockURL=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("Mote")
try? FileManager.default.createDirectory(at:lockURL,withIntermediateDirectories:true)
let instanceFD=Darwin.open(lockURL.appendingPathComponent("instance.lock").path,O_CREAT|O_RDWR,0o600)
guard instanceFD>=0,flock(instanceFD,LOCK_EX|LOCK_NB)==0 else{exit(0)}
let app=NSApplication.shared;let delegate=AppDelegate();app.delegate=delegate;app.finishLaunching();delegate.applicationDidFinishLaunching(Notification(name:NSApplication.didFinishLaunchingNotification));withExtendedLifetime(delegate){app.run()}}}
