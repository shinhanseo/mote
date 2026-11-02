import AppKit

MainActor.assumeIsolated {
    func expect(_ result:Bool,_ message:String){precondition(result,message)}
    let m=Monitor();m.ledger=NotificationLedger();m.completionAlerts=true;m.attentionAlerts=true;m.errorAlerts=true;m.muted=false;m.pauseUntil=nil
    var delivered=[(count:Int,title:String)]()
    m.onNotice={jobs,title,_ in delivered.append((jobs.count,title))}
    let running=Job(id:"chat-a",title:"테스트 작업 A",project:"fixture",status:"inProgress",turn:"turn-a",startedAt:Date().timeIntervalSince1970)
    m.apply(.success([running]))
    expect(m.active==1 && m.currentJobs.count==1,"new running conversation retained")
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
    MotePreferences.store.removePersistentDomain(forName:ProcessInfo.processInfo.environment["MOTE_TEST_SUITE"]!)
    print("PASS: real Monitor lifecycle, approval, question, resume, grouped completion, read, cleanup/undo, defer/restore, parallel work, snooze")
}
