import AppKit
import Combine
import CryptoKit

/// Explicitly enabled relay; unsigned builds cannot initialize CloudKit.
@MainActor final class MobileNotifier:ObservableObject {
    @Published var enabled=false
    private let defaults:UserDefaults
    @Published var shareTitles=false {didSet{defaults.set(shareTitles,forKey:"mobileShareTitles")}}
    @Published var issue:String?
    private let relay=CloudRelay()
    private let installationID:String
    private var pending=[RelayEvent]()
    private var sending=false
    init(defaults:UserDefaults = .standard) {
        self.defaults=defaults
        shareTitles=defaults.bool(forKey:"mobileShareTitles")
        if let data=defaults.data(forKey:"mobilePending"),let saved=try? JSONDecoder().decode([RelayEvent].self,from:data){pending=saved.filter{Date().timeIntervalSince($0.createdAt)<3600}.map{RelayEvent(id:$0.id,kind:$0.kind,title:"",macName:$0.macName,createdAt:$0.createdAt)}}
        if let id=defaults.string(forKey:"mobileInstallationID"){installationID=id}
        else{let id=UUID().uuidString;defaults.set(id,forKey:"mobileInstallationID");installationID=id}
    }
    func disconnect(){enabled=false;pending=[];savePending();defaults.set(false,forKey:"mobileRelayEnabled")}
    func restore() async {if defaults.bool(forKey:"mobileRelayEnabled"){await connect()}}
    func connect() async {
        do {
            try await relay.checkAccount()
            try await relay.registerMac(id:installationID,name:Host.current().localizedName ?? "Mac")
            enabled=true;defaults.set(true,forKey:"mobileRelayEnabled");issue=nil;await flush()
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
    func send(thread:String,turn:String,kind:String,title:String,privateMode:Bool) async {
        guard enabled,["completed","approval","answer"].contains(kind) else{return}
        let fingerprint=[installationID,thread,turn,kind].joined(separator:"\n")
        let id=SHA256.hash(data:Data(fingerprint.utf8)).map{String(format:"%02x",$0)}.joined()
        let event=RelayEvent(id:id,kind:kind,title:shareTitles && !privateMode ? title:"",macName:Host.current().localizedName ?? "Mac",createdAt:Date())
        if !pending.contains(where:{$0.id==id}){pending.append(event);pending=Array(pending.suffix(100));savePending()}
        await flush()
    }
    private func savePending(){if let data=try? JSONEncoder().encode(pending.map{RelayEvent(id:$0.id,kind:$0.kind,title:"",macName:$0.macName,createdAt:$0.createdAt)}){defaults.set(data,forKey:"mobilePending")}}
    func flush() async {
        guard enabled,!sending else{return};sending=true;defer{sending=false}
        pending=pending.filter{Date().timeIntervalSince($0.createdAt)<3600};savePending()
        while enabled,let event=pending.first {
            do{try await relay.send(event);pending.removeAll{$0.id==event.id};savePending();issue=nil}
            catch{issue=error.localizedDescription;break}
        }
    }
}
