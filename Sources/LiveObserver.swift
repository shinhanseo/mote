import Foundation
import Darwin

// Private desktop IPC: passive subscriptions only. No tool decisions or user replies are sent.
struct LiveState {
    var runtime: [String:Any] = [:]
    var requestIDs: [String] = []
    var requestReasons:[String:String]=[:]
    var revision: Int = -1
    var unread:Bool?
    struct Turn {var id:String;var status:String;var started:Double}
    var turns:[String:Turn]=[:]
    var latestTurn:Turn? {turns.values.max{$0.started<$1.started}}
    mutating func capture(_ key:String,_ object:[String:Any]){
        guard let id=object["turnId"] as? String,let status=object["status"] as? String else{return}
        turns[key]=Turn(id:id,status:status,started:object["turnStartedAtMs"] as? Double ?? 0)
        if turns.count>200 {turns=Dictionary(uniqueKeysWithValues:turns.sorted{$0.value.started>$1.value.started}.prefix(100).map{($0.key,$0.value)})}
    }
    mutating func captureHistory(_ history:[String:Any]){
        guard let store=history["history"] as? [String:Any],let entities=store["entitiesByKey"] as? [String:[String:Any]] else{return}
        for (key,object) in entities {capture(key,object)}
    }
    var waiting: String? {
        guard runtime["type"] as? String == "active" else { return nil }
        let flags = runtime["activeFlags"] as? [String] ?? []
        if flags.contains("waitingOnApproval") { return "approval" }
        if flags.contains("waitingOnUserInput") { return "answer" }
        return nil
    }
    mutating func apply(_ change:[String:Any]) -> Bool {
        guard let rev=change["revision"] as? Int else { return false }
        if change["type"] as? String == "snapshot", let state=change["conversationState"] as? [String:Any] {
            turns.removeAll()
            if let history=state["turnHistory"] as? [String:Any] {captureHistory(history)}
            if let list=state["turns"] as? [[String:Any]] {for (i,object) in list.enumerated(){capture("legacy:\(i)",object)}}
            unread=state["hasUnreadTurn"] as? Bool
            runtime=state["threadRuntimeStatus"] as? [String:Any] ?? [:]
            requestReasons=[:]
            for request in state["requests"] as? [[String:Any]] ?? [] {if let method=request["method"] as? String,let reason=PresentationPolicy.requestLabel(method),let id=request["id"] {requestReasons[String(describing:id)]=reason}}
            requestIDs=(state["requests"] as? [[String:Any]] ?? []).compactMap { request in
                (request["id"] ?? request["requestId"]).map { String(describing:$0) }
            }
            revision=rev;return true
        }
        guard change["type"] as? String == "patches", change["baseRevision"] as? Int == revision, let patches=change["patches"] as? [[String:Any]] else { return false }
        for patch in patches {
            guard let path=patch["path"] as? [Any],let first=path.first as? String else {continue}
            let op=patch["op"] as? String ?? ""
            if first == "turnHistory" {
                if path.count==1,let history=patch["value"] as? [String:Any]{turns.removeAll();captureHistory(history)}
                else if path.count>=4,path[1] as? String == "history",path[2] as? String == "entitiesByKey",let key=path[3] as? String {
                    if path.count==4 {if op=="remove"{turns.removeValue(forKey:key)}else if let object=patch["value"] as? [String:Any]{capture(key,object)}}
                    else if path.count==5,let field=path[4] as? String,var turn=turns[key]{
                        if field=="status",let value=patch["value"] as? String {turn.status=value}
                        if field=="turnStartedAtMs",let value=patch["value"] as? Double {turn.started=value}
                        turns[key]=turn
                    }
                }
            }
            if first == "turns",path.count>=2,let index=path[1] as? Int {
                let key="legacy:\(index)"
                if path.count==2,let object=patch["value"] as? [String:Any]{capture(key,object)}
                else if path.count==3,path[2] as? String == "status",var turn=turns[key],let value=patch["value"] as? String {turn.status=value;turns[key]=turn}
            }
            if first == "hasUnreadTurn" {unread=patch["value"] as? Bool}
            if first == "threadRuntimeStatus" {
                runtime=Self.edit(runtime,path:Array(path.dropFirst()),value:patch["value"] ?? NSNull(),remove:op=="remove") as? [String:Any] ?? [:]
            }
            if first == "requests" {
                // IDs are used only to distinguish consecutive requests, never store request contents.
                if path.count==1,let list=patch["value"] as? [[String:Any]] {requestIDs=list.compactMap{($0["id"] ?? $0["requestId"]).map{String(describing:$0)}};requestReasons=[:];for request in list{if let id=request["id"],let method=request["method"] as? String,let reason=PresentationPolicy.requestLabel(method){requestReasons[String(describing:id)]=reason}}}
                else if path.count==2,let index=path[1] as? Int {
                    if op=="remove",requestIDs.indices.contains(index){requestReasons.removeValue(forKey:requestIDs[index]);requestIDs.remove(at:index)}
                    else if let request=patch["value"] as? [String:Any],let id=request["id"] ?? request["requestId"] {
                        if let method=request["method"] as? String,let reason=PresentationPolicy.requestLabel(method){requestReasons[String(describing:id)]=reason}
                        if requestIDs.indices.contains(index){requestIDs[index]=String(describing:id)}else if index==requestIDs.count{requestIDs.append(String(describing:id))}
                    }
                }
            }
        }
        revision=rev;return true
    }
    static func edit(_ root:Any,path:[Any],value:Any,remove:Bool)->Any {
        guard let head=path.first else{return remove ? NSNull():value}
        if let key=head as? String {var object=root as? [String:Any] ?? [:];if path.count==1 && remove{object.removeValue(forKey:key)}else{object[key]=edit(object[key] ?? [:],path:Array(path.dropFirst()),value:value,remove:remove)};return object}
        if let index=head as? Int {var array=root as? [Any] ?? [];guard index>=0,index<=array.count else{return root};if path.count==1 && remove {if index<array.count{array.remove(at:index)}}else if index<array.count{array[index]=edit(array[index],path:Array(path.dropFirst()),value:value,remove:remove)}else{array.append(value)};return array}
        return root
    }
}
final class LiveObserver: @unchecked Sendable {
    private let lock=NSLock();private var ids=[String]()
    var onState: (@Sendable (String,LiveState)->Void)?
    var onDiagnostic:(@Sendable(String?)->Void)?
    var onConnection: (@Sendable (Bool)->Void)?
    func observe(_ ids:[String]) {lock.lock();self.ids=ids;lock.unlock()}
    func start(){DispatchQueue(label:"mote.codex.ipc",qos:.utility).async{self.run()}}
    private func send(_ object:[String:Any],_ fd:Int32)->Bool {
        guard let data=try? JSONSerialization.data(withJSONObject:object) else{return false}
        var length=UInt32(data.count).littleEndian;var frame=Data(bytes:&length,count:4);frame.append(data)
        return frame.withUnsafeBytes{bytes in var offset=0;while offset<bytes.count {let n=Darwin.send(fd,bytes.baseAddress!.advanced(by:offset),bytes.count-offset,0);if n<=0{return false};offset+=n};return true}
    }
    private func run(){while true{connect();onConnection?(false);Thread.sleep(forTimeInterval:2)}}
    private func connect(){
        let home=ProcessInfo.processInfo.environment["CODEX_HOME"] ?? NSHomeDirectory()+"/.codex"
        let path=home+"/ipc/ipc.sock";var info=stat()
        guard lstat(path,&info)==0,info.st_uid==getuid(),(info.st_mode & S_IFMT)==S_IFSOCK else{return}
        let fd=socket(AF_UNIX,SOCK_STREAM,0);guard fd>=0 else{return};defer{close(fd)}
        var noSignal:Int32=1;setsockopt(fd,SOL_SOCKET,SO_NOSIGPIPE,&noSignal,socklen_t(MemoryLayout<Int32>.size))
        var timeout=timeval(tv_sec:2,tv_usec:0);setsockopt(fd,SOL_SOCKET,SO_SNDTIMEO,&timeout,socklen_t(MemoryLayout<timeval>.size))
        var address=sockaddr_un();address.sun_family=sa_family_t(AF_UNIX)
        guard path.utf8.count<MemoryLayout.size(ofValue:address.sun_path) else{return}
        withUnsafeMutableBytes(of:&address.sun_path){dest in for (i,b) in path.utf8.enumerated(){dest[i]=b}}
        let result=withUnsafePointer(to:&address){$0.withMemoryRebound(to:sockaddr.self,capacity:1){Darwin.connect(fd,$0,socklen_t(MemoryLayout<sockaddr_un>.size))}}
        guard result==0 else{return}
        guard send(["type":"request","requestId":UUID().uuidString,"method":"initialize","params":["clientType":"mote-monitor"],"version":0],fd) else{return}
        var client:String?;var buffer=Data();var subscribed=Set<String>();var states=[String:LiveState]();var bytes=[UInt8](repeating:0,count:65536)
        var lastFrame=Date()
        while true {
            lock.lock();let wanted=Set(ids);lock.unlock()
            if let client {
                for id in wanted.subtracting(subscribed) {guard send(["type":"broadcast","method":"thread-stream-following-changed","sourceClientId":client,"version":1,"params":["conversationId":id,"hostId":"local","following":true]],fd) else{return}}
                for id in subscribed.subtracting(wanted) {_ = send(["type":"broadcast","method":"thread-stream-following-changed","sourceClientId":client,"version":1,"params":["conversationId":id,"hostId":"local","following":false]],fd);states.removeValue(forKey:id)}
                subscribed=wanted
            }
            var poller=pollfd(fd:fd,events:Int16(POLLIN),revents:0)
            let ready=poll(&poller,1,1000)
            if ready<0{return};if ready==0 {if client==nil && Date().timeIntervalSince(lastFrame)>5{return};continue}
            let count=recv(fd,&bytes,bytes.count,0);guard count>0 else{return};buffer.append(contentsOf:bytes.prefix(count))
            while buffer.count>=4 {
                let size=buffer.prefix(4).enumerated().reduce(0){$0 | (Int($1.element)<<($1.offset*8))}
                guard size>0,size<=32*1024*1024 else{return};guard buffer.count>=size+4 else{break}
                let data=Data(buffer.dropFirst(4).prefix(size));buffer.removeFirst(size+4);lastFrame=Date()
                guard let message=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any] else{return}
                if message["type"] as? String == "response", message["method"] as? String == "initialize",let result=message["result"] as? [String:Any],let id=result["clientId"] as? String {client=id;onDiagnostic?(nil);onConnection?(true)}
                if message["type"] as? String == "client-discovery-request",let request=message["requestId"] {_ = send(["type":"client-discovery-response","requestId":request,"response":["canHandle":false]],fd)}
                if message["method"] as? String == "thread-stream-state-changed",message["version"] as? Int != 11 {onDiagnostic?("현재 Codex 실시간 형식은 아직 지원하지 않아요. 기본 기록 감지는 계속됩니다.")}
                guard message["type"] as? String == "broadcast",message["method"] as? String == "thread-stream-state-changed",message["version"] as? Int == 11,let params=message["params"] as? [String:Any],params["hostId"] as? String == "local",let id=params["conversationId"] as? String,wanted.contains(id),let change=params["change"] as? [String:Any] else{continue}
                var state=states[id] ?? LiveState()
                if state.apply(change){states[id]=state;onState?(id,state)}else{
                    // Revision gap: discard stale status, reconnect for a fresh snapshot.
                    return
                }
            }
        }
    }
}
