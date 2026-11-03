import AppKit
import Combine
import CryptoKit

/// Explicitly enabled relay; unsigned builds cannot initialize CloudKit.
@MainActor final class MobileNotifier:ObservableObject {
    @Published var enabled=false
    @Published var awayOnly=true {didSet{defaults.set(awayOnly,forKey:"mobileAwayOnly")}}
    private let defaults:UserDefaults
    @Published var shareTitles=false {didSet{defaults.set(shareTitles,forKey:"mobileShareTitles")}}
    @Published var remoteReplies=false {didSet{defaults.set(remoteReplies,forKey:"mobileRemoteReplies")}}
    private var routes=[String:ReplyRoute]()
    private var replyTask:Task<Void,Never>?
    @Published var issue:String?
    private let relay=CloudRelay()
    private let installationID:String
    private var pending=[RelayEvent]()
    private var sending=false
    init(defaults:UserDefaults = .standard) {
        self.defaults=defaults
        remoteReplies=defaults.bool(forKey:"mobileRemoteReplies")
        if let data=defaults.data(forKey:"mobileReplyRoutes"),let saved=try? JSONDecoder().decode([String:ReplyRoute].self,from:data){routes=saved}
        awayOnly=defaults.object(forKey:"mobileAwayOnly") as? Bool ?? true
        shareTitles=defaults.bool(forKey:"mobileShareTitles")
        if let data=defaults.data(forKey:"mobilePending"),let saved=try? JSONDecoder().decode([RelayEvent].self,from:data){pending=saved.filter{Date().timeIntervalSince($0.createdAt)<3600}.map{RelayEvent(id:$0.id,kind:$0.kind,title:"",macName:$0.macName,createdAt:$0.createdAt,replyMac:$0.replyMac,replyUntil:$0.replyUntil)}}
        if let id=defaults.string(forKey:"mobileInstallationID"){installationID=id}
        else{let id=UUID().uuidString;defaults.set(id,forKey:"mobileInstallationID");installationID=id}
    }
    func disconnect(){replyTask?.cancel();replyTask=nil;enabled=false;pending=[];savePending();defaults.set(false,forKey:"mobileRelayEnabled")}
    func restore() async {if defaults.bool(forKey:"mobileRelayEnabled"){await connect()}}
    func connect() async {
        do {
            try await relay.checkAccount()
            try await relay.registerMac(id:installationID,name:Host.current().localizedName ?? "Mac")
            enabled=true;defaults.set(true,forKey:"mobileRelayEnabled");issue=nil;await flush();startReplyReceiver()
        }catch{enabled=false;issue=error.localizedDescription}
    }
    func testSuite(_ label:String) async {
        let previous=shareTitles;shareTitles=true
        for (index,kind) in ["completed","approval","answer"].enumerated(){
            await send(thread:"test-"+kind,turn:UUID().uuidString,kind:kind,title:"[테스트 \(index+1)/3 · \(label)] \(kind=="completed" ? "로그인 화면 수정":kind=="approval" ? "명령 실행 승인":"진행 방식 선택")",privateMode:false)
            if issue != nil{break}
            try? await Task.sleep(nanoseconds:8_000_000_000)
        }
        shareTitles=previous
    }
    func test() async {await send(thread:"test",turn:UUID().uuidString,kind:"completed",title:"",privateMode:true)}
    static func shouldSend(awayOnly:Bool,locked:Bool,idleSeconds:Double)->Bool {
        !awayOnly || locked || idleSeconds>=300
    }
    func send(thread:String,turn:String,kind:String,title:String,privateMode:Bool,requests:[String]=[]) async {
        guard enabled,["completed","approval","answer"].contains(kind) else{return}
        let fingerprint=([installationID,thread,turn,kind]+requests.sorted()).joined(separator:"\n")
        let id=SHA256.hash(data:Data(fingerprint.utf8)).map{String(format:"%02x",$0)}.joined()
        let acceptsReply=remoteReplies && kind=="answer" && requests.count==1
        let until=Date().addingTimeInterval(1800)
        if acceptsReply {routes[id]=ReplyRoute(thread:thread,turn:turn,requests:requests,expiresAt:until);saveRoutes()}
        let event=RelayEvent(id:id,kind:kind,title:shareTitles && !privateMode ? title:"",macName:Host.current().localizedName ?? "Mac",createdAt:Date(),replyMac:acceptsReply ? installationID:nil,replyUntil:acceptsReply ? until:nil)
        if !pending.contains(where:{$0.id==id}){pending.append(event);pending=Array(pending.suffix(100));savePending()}
        await flush()
    }
    private func savePending(){if let data=try? JSONEncoder().encode(pending.map{RelayEvent(id:$0.id,kind:$0.kind,title:"",macName:$0.macName,createdAt:$0.createdAt,replyMac:$0.replyMac,replyUntil:$0.replyUntil)}){defaults.set(data,forKey:"mobilePending")}}
    private func saveRoutes(){routes=Dictionary(uniqueKeysWithValues:routes.sorted{$0.value.expiresAt>$1.value.expiresAt}.prefix(100).map{($0.key,$0.value)});if let data=try? JSONEncoder().encode(routes){defaults.set(data,forKey:"mobileReplyRoutes")}}
    private func startReplyReceiver(){
        guard replyTask==nil else{return}
        replyTask=Task{[weak self] in
            while !Task.isCancelled {
                await self?.receiveReplies()
                do{try await Task.sleep(nanoseconds:15_000_000_000)}catch{break}
            }
        }
    }
    func receiveReplies() async {
        guard enabled,remoteReplies else{return}
        routes=routes.filter{$0.value.expiresAt>Date().addingTimeInterval(-120)};saveRoutes()
        guard !routes.isEmpty else{return}
        do {
            for record in try await relay.queuedReplies(events:Array(routes.keys)) {
                guard enabled,remoteReplies else{return}
                guard let reply=RelayReply.decode(record),reply.macID==installationID,let route=routes[reply.eventID] else{continue}
                var attempted=Set((defaults.stringArray(forKey:"mobileReplyAttempts") ?? []).filter{$0.hasPrefix("reply-") && routes[String($0.dropFirst(6))] != nil})
                guard reply.expiresAt>Date(),route.expiresAt>Date() else{try await relay.updateReply(record,status:"expired",message:"답변 시간이 지났어요.");continue}
                if attempted.contains(reply.id) {try await relay.updateReply(record,status:"unknown",message:"이전 전송 결과를 Mac에서 확인해 주세요.");continue}
                // Persist before dispatch. A crash must never replay a user's answer.
                attempted.insert(reply.id);defaults.set(Array(attempted),forKey:"mobileReplyAttempts")
                try await relay.updateReply(record,status:"delivering")
                guard enabled,remoteReplies else{try await relay.updateReply(record,status:"failed",message:"Mac에서 답변 전송을 껐어요.");return}
                do {
                    try await Task.detached(priority:.utility){try CodexReplyClient().deliver(reply.body,route:route,id:reply.id)}.value
                    try await relay.updateReply(record,status:"delivered",message:"Codex가 답변을 받았어요.")
                }catch {
                    let unknown=(error as? RemoteReplyError) == .uncertain
                    try await relay.updateReply(record,status:unknown ? "unknown":"failed",message:error.localizedDescription)
                }
            }
        }catch{issue=error.localizedDescription}
    }
    func flush() async {
        guard enabled,!sending else{return};sending=true;defer{sending=false}
        pending=pending.filter{Date().timeIntervalSince($0.createdAt)<3600};savePending()
        while enabled,let event=pending.first {
            do{try await relay.send(event);pending.removeAll{$0.id==event.id};savePending();issue=nil}
            catch{issue=error.localizedDescription;break}
        }
    }
}
