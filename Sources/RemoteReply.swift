import Foundation
#if os(macOS)
import Darwin

struct ReplyRoute:Codable {
 let thread:String
 let turn:String
 let requests:[String]
 let expiresAt:Date
}
enum RemoteReplyError:LocalizedError,Equatable {
 case unavailable,stale,unsupported,uncertain
 var errorDescription:String? {switch self {
 case .unavailable:return "Mac의 Codex 연결을 확인해 주세요."
 case .stale:return "질문이 바뀌었거나 이미 답변했어요. Mac에서 확인해 주세요."
 case .unsupported:return "이 질문 유형은 아직 Mac에서 답변해야 해요."
 case .uncertain:return "Codex 수신 여부를 확인할 수 없어요. 중복 전송하지 말고 Mac에서 확인해 주세요."
 }}
}
/// One short-lived connection per explicit reply. Never launches another Codex process.
final class CodexReplyClient {
 private var fd:Int32 = -1
 private var client=""
 private var buffer=Data()
 deinit {if fd>=0{close(fd)}}
 private func send(_ object:[String:Any]) throws {
  let data=try JSONSerialization.data(withJSONObject:object)
  var n=UInt32(data.count).littleEndian;var frame=Data(bytes:&n,count:4);frame.append(data)
  try frame.withUnsafeBytes{b in var offset=0;while offset<b.count {
   let count=Darwin.send(fd,b.baseAddress!.advanced(by:offset),b.count-offset,0)
   guard count>0 else{throw RemoteReplyError.unavailable};offset+=count
  }}
 }
 private func read(until deadline:Date) throws -> [String:Any] {
  while Date()<deadline {
   if buffer.count>=4 {
    let size=buffer.prefix(4).enumerated().reduce(0){$0 | (Int($1.element)<<($1.offset*8))}
    guard size>0,size<32*1024*1024 else{throw RemoteReplyError.unavailable}
    if buffer.count>=size+4 {
     let data=Data(buffer.dropFirst(4).prefix(size));buffer.removeFirst(size+4)
     guard let message=try JSONSerialization.jsonObject(with:data) as? [String:Any] else{throw RemoteReplyError.unavailable}
     if message["type"] as? String == "client-discovery-request",let id=message["requestId"] {
      try send(["type":"client-discovery-response","requestId":id,"response":["canHandle":false]]);continue
     }
     return message
    }
   }
   var p=pollfd(fd:fd,events:Int16(POLLIN),revents:0)
   guard poll(&p,1,500)>=0 else{throw RemoteReplyError.unavailable}
   if p.revents==0{continue}
   var bytes=[UInt8](repeating:0,count:65536);let count=recv(fd,&bytes,bytes.count,0)
   guard count>0 else{throw RemoteReplyError.unavailable};buffer.append(contentsOf:bytes.prefix(count))
  }
  throw RemoteReplyError.unavailable
 }
 private func request(_ method:String,_ params:[String:Any],version:Int,target:String?=nil) throws -> [String:Any] {
  let id=UUID().uuidString
  var object:[String:Any]=["type":"request","requestId":id,"sourceClientId":client,"method":method,"params":params,"version":version,"timeoutMs":8000]
  if let target{object["targetClientId"]=target}
  try send(object);let end=Date().addingTimeInterval(10)
  while Date()<end{let m=try read(until:end);if m["requestId"] as? String == id,m["type"] as? String == "response" {guard m["resultType"] as? String != "error" else{throw RemoteReplyError.unavailable};return m}}
  throw RemoteReplyError.unavailable
 }
 private func connect() throws {
  let path=(ProcessInfo.processInfo.environment["CODEX_HOME"] ?? NSHomeDirectory()+"/.codex")+"/ipc/ipc.sock"
  var info=stat();guard lstat(path,&info)==0,info.st_uid==getuid(),(info.st_mode & S_IFMT)==S_IFSOCK else{throw RemoteReplyError.unavailable}
  fd=socket(AF_UNIX,SOCK_STREAM,0);guard fd>=0 else{throw RemoteReplyError.unavailable}
  var noSignal:Int32=1;setsockopt(fd,SOL_SOCKET,SO_NOSIGPIPE,&noSignal,socklen_t(MemoryLayout<Int32>.size))
  var timeout=timeval(tv_sec:3,tv_usec:0);setsockopt(fd,SOL_SOCKET,SO_SNDTIMEO,&timeout,socklen_t(MemoryLayout<timeval>.size))
  var address=sockaddr_un();address.sun_family=sa_family_t(AF_UNIX)
  guard path.utf8.count<MemoryLayout.size(ofValue:address.sun_path) else{throw RemoteReplyError.unavailable}
  withUnsafeMutableBytes(of:&address.sun_path){b in for(i,v) in path.utf8.enumerated(){b[i]=v}}
  let ok=withUnsafePointer(to:&address){$0.withMemoryRebound(to:sockaddr.self,capacity:1){Darwin.connect(fd,$0,socklen_t(MemoryLayout<sockaddr_un>.size))}}
  guard ok==0 else{throw RemoteReplyError.unavailable}
  let initialized=try request("initialize",["clientType":"mote-reply"],version:0)
  guard let result=initialized["result"] as? [String:Any],let id=result["clientId"] as? String else{throw RemoteReplyError.unavailable};client=id
 }
 private func snapshot(_ thread:String) throws -> (LiveState,[[String:Any]],String) {
  try send(["type":"broadcast","method":"thread-stream-following-changed","sourceClientId":client,"version":1,"params":["conversationId":thread,"hostId":"local","following":true]])
  let end=Date().addingTimeInterval(8)
  while Date()<end {
   let m=try read(until:end)
   guard m["method"] as? String == "thread-stream-state-changed",m["version"] as? Int == 11,let p=m["params"] as? [String:Any],p["conversationId"] as? String == thread,p["hostId"] as? String == "local",let c=p["change"] as? [String:Any],c["type"] as? String == "snapshot",let state=c["conversationState"] as? [String:Any],let owner=m["sourceClientId"] as? String else{continue}
   var live=LiveState();guard live.apply(c) else{throw RemoteReplyError.unavailable}
   return(live,state["requests"] as? [[String:Any]] ?? [],owner)
  };throw RemoteReplyError.unavailable
 }
 static func validate(_ route:ReplyRoute,state:LiveState,now:Date=Date()) throws {
  guard !(state.runtime["activeFlags"] as? [String] ?? []).contains("waitingOnApproval"),route.expiresAt>now,state.latestTurn?.id==route.turn,state.waiting=="answer",Set(state.requestIDs+state.asyncQuestionIDs)==Set(route.requests),!route.requests.isEmpty else{throw RemoteReplyError.stale}
 }
 func deliver(_ text:String,route:ReplyRoute,id:String) throws {
  guard !text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,text.count<=4000 else{throw RemoteReplyError.unsupported}
  try connect();let (state,requests,owner)=try snapshot(route.thread);try Self.validate(route,state:state)
  let method:String,params:[String:Any],version:Int
  if !requests.isEmpty {
   guard requests.count==1,let r=requests.first,r["method"] as? String == "item/tool/requestUserInput",let requestID=r["id"],let p=r["params"] as? [String:Any],let questions=p["questions"] as? [[String:Any]],questions.count==1,let question=questions.first?["id"] as? String else{throw RemoteReplyError.unsupported}
   method="thread-follower-submit-user-input";version=1
   params=["conversationId":route.thread,"requestId":requestID,"response":["answers":[question:["answers":[text]]]]]
  } else {
   guard state.asyncQuestionIDs.count==1 else{throw RemoteReplyError.unsupported}
   let input:[[String:Any]]=[["type":"text","text":text,"text_elements":[]]]
   if state.latestTurn?.status=="inProgress" {
    method="thread-follower-steer-turn";version=1
    params=["conversationId":route.thread,"input":input,"clientUserMessageId":id]
   } else {
    method="thread-follower-start-turn";version=2
    params=["conversationId":route.thread,"turnStart":["request":["threadId":route.thread,"input":input,"clientUserMessageId":id],"context":["inheritThreadSettings":true]]]
   }
  }
  // Once submitted, an interrupted connection is ambiguous. Never retry it automatically.
  do{_ = try request(method,params,version:version,target:owner)}catch{throw RemoteReplyError.uncertain}
 }
 func probe(_ thread:String) throws -> Bool {
  try connect();let (_,_,owner)=try snapshot(thread)
  _ = try request("thread-follower-read-model-settings",["conversationId":thread],version:1,target:owner)
  return true
 }
}
#endif
