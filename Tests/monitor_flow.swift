import AppKit
import Combine

MainActor.assumeIsolated {
    func expect(_ result:Bool,_ message:String){precondition(result,message)}
    let m=Monitor();m.ledger=NotificationLedger();m.completionAlerts=true;m.attentionAlerts=true;m.errorAlerts=true;m.muted=false;m.pauseUntil=nil
    var delivered=[(count:Int,title:String)]()
    m.onNotice={jobs,title,_ in delivered.append((jobs.count,title))}
    let running=Job(id:"chat-a",title:"테스트 작업 A",project:"fixture",status:"inProgress",turn:"turn-a",startedAt:Date().timeIntervalSince1970)
    m.apply(.success([running]),warning:"fixture history unavailable")
    expect(m.active==1 && m.currentJobs.count==1,"new running conversation retained")
    expect(m.error=="fixture history unavailable","partial records retain warning")
    var state=LiveState()
    expect(state.apply(["type":"snapshot","revision":1,"conversationState":["threadRuntimeStatus":["type":"active","activeFlags":["waitingOnApproval"]],"requests":[["id":"permission-a","method":"item/commandExecution/requestApproval"]]]]),"approval snapshot")
    m.receive("chat-a",state)
    expect(m.waiting==1 && m.fairyStatus=="approval","approval shown")
    expect(m.jobs.first?.reason=="명령 실행 승인이 필요해요","reason displayed")
    expect(delivered.count==1,"approval notification delivered once")
    m.waitSignatures.removeAll();m.liveStates.removeAll();m.receive("chat-a",state)
    expect(delivered.count==1,"reconnect cannot duplicate approval")
    expect(state.apply(["type":"snapshot","revision":2,"conversationState":["threadRuntimeStatus":["type":"active","activeFlags":["waitingOnUserInput"]],"requests":[["id":"question-a","method":"tool/requestUserInput"]]]]),"question snapshot")
    m.receive("chat-a",state)
    expect(m.fairyStatus=="answer" && delivered.count==2,"question notification")
    expect(state.apply(["type":"snapshot","revision":3,"conversationState":["threadRuntimeStatus":["type":"active","activeFlags":[]],"requests":[]]]),"resume")
    m.receive("chat-a",state);expect(m.waiting==0 && m.active==1,"resume clears wait")
    expect(state.apply(["type":"snapshot","revision":4,"conversationState":["threadRuntimeStatus":["type":"idle"],"hasUnreadTurn":true]]),"completed state")
    m.receive("chat-a",state)
    var complete=running;complete.status="completed";complete.readReceipt=true
    m.apply(.success([complete]));m.flushCompletions()
    expect(m.unread==1 && m.fairyStatus=="unread","unread reply retained")
    expect(delivered.count==3,"completion delivered")
    complete.readReceipt=false;m.apply(.success([complete]))
    expect(m.unread==0 && m.currentJobs.count==1,"read clears badge without removing current conversation")
    m.cleanCompleted();expect(m.currentJobs.isEmpty,"cleanup removes completed pin")
    m.undoCleanup();expect(m.currentJobs.count==1,"undo restores pin")
    complete.readReceipt=true;m.apply(.success([complete]));m.deferReply(complete)
    expect(m.unread==0 && m.jobs.first?.status=="deferred","defer lowers unread priority")
    m.restoreReply(complete);expect(m.unread==1,"restore unread priority")
    var b=complete;b.id="chat-b";b.turn="turn-b";b.title="테스트 작업 B"
    m.makeCurrent(b.id);m.apply(.success([complete,b]));expect(m.currentJobs.count==2,"parallel pins retained")
    m.completionQueue=[];m.completionTask?.cancel();m.completionTask=nil;m.ledger=NotificationLedger();delivered=[]
    m.notify(complete);m.notify(b);m.flushCompletions()
    expect(delivered.count==1 && delivered[0].count==2,"simultaneous completions grouped")
    expect(m.menuSummary.contains("답변 2"),"menu summary includes unread count")
    // Real stream/SQLite races: newer live completion must not inherit an old read receipt.
    let r=Monitor();r.onNotice={_,_,_ in};r.completionAlerts=true;r.muted=false;r.pauseUntil=nil
    var oldRead=complete;oldRead.readReceipt=false;oldRead.startedAt=100
    r.apply(.success([oldRead]))
    var fresh=LiveState();fresh.runtime=["type":"idle"];fresh.unread=true
    fresh.turns=["new":LiveState.Turn(id:"new-turn",status:"completed",started:200_000)]
    r.receive(oldRead.id,fresh)
    expect(r.jobs.first?.turn=="new-turn" && r.unread==1,"new live turn ignores old read receipt")
    var persisted=oldRead;persisted.turn="new-turn";persisted.startedAt=200;persisted.readReceipt=false
    r.apply(.success([persisted]));expect(r.unread==0,"matching desktop receipt clears stale live unread")
    var stale=fresh;stale.turns=["old":LiveState.Turn(id:oldRead.turn,status:"inProgress",started:100_000)]
    stale.runtime=["type":"active","activeFlags":["waitingOnApproval"]]
    r.receive(oldRead.id,stale);expect(r.waiting==0,"older stream cannot resurrect approval")
    let before=r.ledger.sent.count;r.notify(persisted)
    expect(r.ledger.sent.count==before,"already-read completion never claims an alert")
    var opened:URL?;r.openURL={opened=$0;return true};r.open(oldRead.id)
    expect(opened?.host=="threads" && opened?.path=="/chat-a" && URLComponents(url:opened!,resolvingAgainstBaseURL:false)?.queryItems?.first?.value=="local","exact local conversation route")
    expect(Monitor.conversationURL("chat-a?hostId=remote")==nil,"reject route injection")
    r.openURL={_ in false};r.open(oldRead.id);expect(r.error != nil,"failed open is visible")
    r.completionTask?.cancel()
    let q=Monitor();q.ledger=NotificationLedger();q.onNotice={_,_,_ in};q.attentionAlerts=true;q.muted=false;q.pauseUntil=nil
    q.apply(.success([running]))
    var async=LiveState()
    let question:[String:Any] = ["type":"agentMessage","id":"question-item","questions":[["title":"fixture"]]]
    expect(async.apply(["type":"snapshot","revision":1,"conversationState":["threadRuntimeStatus":["type":"active","activeFlags":[]],"turnHistory":["history":["entitiesByKey":["turn-a":["turnId":"turn-a","status":"inProgress","turnStartedAtMs":running.startedAt*1000,"items":[question]]]]]]]),"async question snapshot")
    q.receive(running.id,async);expect(q.waiting==1 && q.fairyStatus=="answer" && q.ledger.sent.count==1,"async question alerts without waiting flag")
    q.receive(running.id,async);expect(q.ledger.sent.count==1,"async question deduplicated")
    let reply=String(data:try! JSONSerialization.data(withJSONObject:["questionItemId":async.asyncQuestionIDs[0],"answer":"fixture","question":"fixture"]),encoding:.utf8)!
    let item:[String:Any] = ["type":"userMessage","content":[["type":"text","text":"<send_user_message_question_reply>"+reply+"</send_user_message_question_reply>"]]]
    expect(async.apply(["type":"patches","baseRevision":1,"revision":2,"patches":[["op":"add","path":["turnHistory","history","entitiesByKey","turn-a","items",1],"value":item]]]),"question reply patch")
    q.receive(running.id,async);expect(q.waiting==0,"submitted answer clears async wait")
    m.pause();m.notify(running);expect(delivered.count==1,"snooze suppresses notifications")
    m.resume();m.completionTask?.cancel()
    let usageEvent:[String:Any] = ["timestamp":"2026-11-02T03:00:00.000Z","payload":["rate_limits":["limit_id":"codex","primary":["used_percent":35.0,"window_minutes":300,"resets_at":1793608967],"secondary":["used_percent":100.0,"window_minutes":10080]]]]
    let usage=UsageSnapshot.parse(try! JSONSerialization.data(withJSONObject:usageEvent))!
    expect(usage.windows[0].remaining==65 && usage.windows[1].remaining==0,"real remaining quota, not token balance")
    expect(usage.windows[0].expired(Date.distantFuture),"elapsed reset must not pretend to have refilled")
    expect(UsageSnapshot.parse(Data("{}".utf8))==nil,"missing quota is unavailable, not zero")
    var invalid=usageEvent;invalid["payload"]=["rate_limits":["primary":["used_percent":101,"window_minutes":300]]]
    expect(UsageSnapshot.parse(try! JSONSerialization.data(withJSONObject:invalid))==nil,"reject invalid percentages")
    let resetNow=Date(timeIntervalSince1970:1000)
    var resetPolicy=UsageResetPolicy(pending:["300":1001,"10080":1001],delivered:[])
    expect(resetPolicy.due(now:resetNow,short:true,weekly:true).isEmpty,"reset cannot notify early")
    expect(resetPolicy.due(now:resetNow.addingTimeInterval(2),short:true,weekly:false)==[300],"independent reset switches")
    expect(resetPolicy.due(now:resetNow.addingTimeInterval(3),short:true,weekly:true).isEmpty,"reset delivered only once")
    resetPolicy.pending=["300":1]
    expect(resetPolicy.due(now:resetNow,short:true,weekly:true).isEmpty,"skip old reset after sleep")
    let watch=Monitor();watch.ledger=NotificationLedger();watch.liveConnected=true;watch.reminderEnabled=true;watch.reminderMinutes=5;watch.attentionAlerts=true;watch.muted=false;watch.pauseUntil=nil
    var watchCount=0;watch.onNotice={_,_,_ in watchCount += 1}
    var waitingJob=running;waitingJob.status="answer";waitingJob.waitSince=Date().addingTimeInterval(-301)
    watch.jobs=[waitingJob];watch.checkWaitReminders();watch.checkWaitReminders()
    expect(watchCount==1,"one reminder per unresolved request")
    waitingJob.status="inProgress";watch.jobs=[waitingJob];watch.checkWaitReminders()
    expect(watchCount==1,"resolved request cannot remind")
    watch.receiveNetwork(false);watch.receiveNetwork(false)
    expect(watchCount==2 && watch.activityLabel(running.id).contains("네트워크"),"offline notifies once and overrides activity caption")
    watch.networkAvailable=true;watch.lastActivity[running.id]=Date().addingTimeInterval(-601)
    expect(watch.activityLabel(running.id).contains("오래 변화 없음"),"long silence is labeled without claiming failure")
    let policyNow=Date()
    let low=UsageSnapshot(recorded:policyNow,windows:[UsageSnapshot.Window(used:96,minutes:300,reset:policyNow.addingTimeInterval(3600))])
    var thresholds=UsageThresholdPolicy(sent:[])
    expect(thresholds.observe(low,now:policyNow).count==1,"initial 4% only emits urgent threshold")
    expect(thresholds.observe(low,now:policyNow).isEmpty,"threshold cannot duplicate")
    let staleQuota=UsageSnapshot(recorded:policyNow.addingTimeInterval(-1000),windows:low.windows)
    var stalePolicy=UsageThresholdPolicy(sent:[])
    expect(stalePolicy.observe(staleQuota,now:policyNow).isEmpty,"stale quota cannot alert")
    let notice=SnoozedNotice(jobs:[waitingJob],due:policyNow)
    expect(notice.unresolved(in:[complete]).isEmpty,"snooze cannot resurrect resolved turn")
    let privateMonitor=Monitor();privateMonitor.jobs=[complete];privateMonitor.privacyMode=true
    expect(privateMonitor.visibleTitle(complete)=="비공개 대화","privacy hides title")
    privateMonitor.privacyMode=false
    var awayDelivered=0;privateMonitor.onNotice={_,_,_ in awayDelivered += 1}
    privateMonitor.setAway(true);privateMonitor.deliver([complete],title:"test",body:"fixture",sound:false,identifier:"fixture")
    expect(awayDelivered==0,"away suppresses delivery")
    privateMonitor.jobs=[];privateMonitor.setAway(false);expect(awayDelivered==0,"resolved away items excluded")
    let sn=Monitor();sn.jobs=[Job(id:"snooze",title:"fixture",project:"fixture",status:"answer",turn:"t")];sn.muted=false;sn.pauseUntil=nil
    var snCount=0;sn.onNotice={_,_,_ in snCount += 1}
    sn.snooze(["snooze"],now:policyNow)
    sn.deliver(sn.jobs,title:"test",body:"fixture",sound:false,identifier:"sn")
    expect(snCount==0,"snoozed thread suppresses immediate toast")
    sn.checkSnoozes(now:policyNow.addingTimeInterval(601));sn.checkSnoozes(now:policyNow.addingTimeInterval(602))
    expect(snCount==1,"snooze resumes once after ten minutes")
    var twenties=UsageThresholdPolicy(sent:[])
    let twenty=UsageSnapshot(recorded:policyNow,windows:[UsageSnapshot.Window(used:81,minutes:300,reset:policyNow.addingTimeInterval(3600))])
    expect(twenties.observe(twenty,now:policyNow).first?.1==20,"20 percent warning")
    expect(twenties.observe(low,now:policyNow).first?.1==5,"5 percent warning is independent")

    let releaseFixture:[String:Any]=["tag_name":"v0.3.10","draft":false,"prerelease":false,"assets":[["state":"uploaded","browser_download_url":"https://github.com/shinhanseo/mote/releases/download/v0.3.10/Mote-0.3.10.dmg"]]]
    let published=PublishedRelease.parse(try! JSONSerialization.data(withJSONObject:releaseFixture))!
    expect(published.isNewer(than:"0.3.9"),"release versions compare numerically")
    expect(!published.isNewer(than:"0.3.10") && !published.isNewer(than:"0.4.0"),"equal and older versions are not updates")
    var draft=releaseFixture;draft["prerelease"]=true
    expect(PublishedRelease.parse(try! JSONSerialization.data(withJSONObject:draft))==nil,"skip prereleases")
    var malicious=releaseFixture;malicious["assets"]=[["state":"uploaded","browser_download_url":"https://example.com/Mote.dmg"]]
    expect(PublishedRelease.parse(try! JSONSerialization.data(withJSONObject:malicious))==nil,"only expected release assets can open")
    _ = NSApplication.shared
    let hiddenPanel=MotePanel(contentRect:NSRect(x:0,y:0,width:100,height:100),styleMask:.borderless,backing:.buffered,defer:true)
    hiddenPanel.contentView=NSView();hiddenPanel.orderOut(nil)
    expect(hiddenPanel.contentView==nil,"closing the panel releases its rendering tree")
    for kind in ["idle","inProgress","approval","answer","unread","failed"] {
        for frame in 0..<4 {
            let image=MenuFairy.image(state:kind,frame:frame)
            expect(image.isTemplate && image.size==NSSize(width:28,height:22),"menu frames retain native template size")
            expect(image.representations.count==2,"menu frame must be rasterized for 1x and 2x")
        }
    }
    let statusItem=NSStatusBar.system.statusItem(withLength:NSStatusItem.variableLength)
    let menu=MenuFairy(button:statusItem.button);menu.update("inProgress")
    if let button=statusItem.button {
        let reserved=button.image
        let overlays=button.subviews.filter{$0.identifier?.rawValue=="mote-fairy-layer"}
        expect(overlays.count==1 && overlays[0].layer?.contents != nil,"dedicated icon layer renders a frame")
        expect(overlays[0].layer?.animation(forKey:"mote.frames") != nil || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,"compositor animates without a main-thread timer")
        expect(!overlays[0].frame.isEmpty,"native status button reserves visible icon bounds")
        if let contents=overlays[0].layer?.contents,CFGetTypeID(contents as CFTypeRef)==CGImage.typeID {
            let cg=contents as! CGImage
            let bitmap=NSBitmapImageRep(cgImage:cg)
            var visible=false
            for x in 0..<bitmap.pixelsWide {for y in 0..<bitmap.pixelsHigh {if (bitmap.colorAt(x:x,y:y)?.alphaComponent ?? 0)>0.1 {visible=true;break}}}
            expect(visible,"compositor frame cannot be transparent")
        }else{expect(false,"compositor contents must be an image")}
        expect(overlays[0].hitTest(.zero)==nil,"icon view must pass clicks through to status button")
        menu.update("answer")
        expect(button.image === reserved,"state changes must not replace the native button image")
    }
    NSStatusBar.system.removeStatusItem(statusItem)
    print("PASS: closed panel release, Retina templates, isolated icon rendering, click-through")
    var jobChanges=0
    let observation=m.$jobs.dropFirst().sink{_ in jobChanges += 1}
    m.reconcile();let unchangedCount=jobChanges;m.reconcile()
    expect(jobChanges==unchangedCount,"unchanged jobs must not invalidate SwiftUI")
    withExtendedLifetime(observation){}
    let cachePath=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer{try? FileManager.default.removeItem(at:cachePath)}
    func quota(_ used:Int)->Data {Data("{\"timestamp\":\"2026-11-02T00:00:00.000Z\",\"payload\":{\"rate_limits\":{\"primary\":{\"used_percent\":\(used),\"window_minutes\":300}}}}\n".utf8)}
    try! quota(10).write(to:cachePath)
    expect(UsageSnapshot.readFile(cachePath.path)?.windows.first?.used==10,"first usage read")
    expect(UsageSnapshot.readFile(cachePath.path)?.windows.first?.used==10,"unchanged usage cache")
    let append=try! FileHandle(forWritingTo:cachePath);try! append.seekToEnd();try! append.write(contentsOf:quota(20));try! append.close()
    expect(UsageSnapshot.readFile(cachePath.path)?.windows.first?.used==20,"usage cache invalidated by append")
    try! Data("unrelated text\n".utf8).write(to:cachePath)
    expect(UsageSnapshot.readFile(cachePath.path)==nil,"truncation cannot retain old quota")
    try! quota(30).write(to:cachePath,options:.atomic)
    expect(UsageSnapshot.readFile(cachePath.path)?.windows.first?.used==30,"replacement invalidates cached empty file")
    print("PASS: unchanged model does not republish; quota cache handles append, truncate, replacement")
    let partial=Monitor();partial.ledger=NotificationLedger();partial.onNotice={_,_,_ in}
    let unknown=Job(id:"partial-chat",title:"fixture",project:"fixture",status:"unknown",turn:"")
    partial.apply(.success([unknown]),warning:"fixture history unavailable")
    var partialState=LiveState()
    expect(partialState.apply(["type":"snapshot","revision":1,"conversationState":["threadRuntimeStatus":["type":"active","activeFlags":["waitingOnApproval"]],"requests":[["id":"partial-request","method":"item/commandExecution/requestApproval"]]]]),"partial record snapshot")
    partial.receive("partial-chat",partialState)
    expect(partial.waiting==1 && partial.jobs.first?.status=="approval","unknown history must not block live approvals")
    expect(Panel(model:partial).headline.contains("승인을"),"live waiting headline takes precedence over partial record warning")
    expect(partial.error != nil,"partial record warning is retained alongside live status")
    print("PASS: unavailable history retains live approval detection and headline")
    m.apply(.success([]))
    m.apply(.failure(LocalReader.failure("Codex 기록 읽기 실패",code:3)))
    expect(Panel(model:m).headline==L10n.text("작업 상태를 확인할 수 없어요."),"record read failure cannot present idle")
    expect(m.error==L10n.text("Codex 기록 읽기 실패"),"reader error should have actionable localized text")
    m.apply(.success([]))
    expect(m.error==nil,"a successful retry clears the reader error")
    print("PASS: record failure shows unknown status and recovery clears error")
    MotePreferences.store.removePersistentDomain(forName:ProcessInfo.processInfo.environment["MOTE_TEST_SUITE"]!)
    print("PASS: real Monitor lifecycle, approval, question, resume, grouped completion, read, cleanup/undo, defer/restore, parallel work, snooze")
}
