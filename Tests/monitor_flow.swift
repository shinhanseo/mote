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
    m.pause();m.notify(running);expect(delivered.count==1,"snooze suppresses notifications")
    m.resume();m.completionTask?.cancel()
    MotePreferences.store.removePersistentDomain(forName:ProcessInfo.processInfo.environment["MOTE_TEST_SUITE"]!)
    print("PASS: real Monitor lifecycle, approval, question, resume, grouped completion, read, cleanup/undo, defer/restore, parallel work, snooze")
}
