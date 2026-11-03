import AppKit
import Combine
import CryptoKit

/// Opt-in adapter for the Mac monitor. It is deliberately outside the shipping
/// Sources glob until the Mac App ID and CloudKit provisioning are configured.
@MainActor final class MobileNotifier:ObservableObject {
    @Published var enabled=false
    @Published var shareTitles=false
    @Published var issue:String?
    private let relay=CloudRelay()
    private let installationID:String
    init(defaults:UserDefaults = .standard) {
        if let id=defaults.string(forKey:"mobileInstallationID"){installationID=id}
        else{let id=UUID().uuidString;defaults.set(id,forKey:"mobileInstallationID");installationID=id}
    }
    func connect() async {
        do {
            try await relay.checkAccount()
            try await relay.registerMac(id:installationID,name:Host.current().localizedName ?? "Mac")
            enabled=true;issue=nil
        }catch{enabled=false;issue=error.localizedDescription}
    }
    func send(thread:String,turn:String,kind:String,title:String,privateMode:Bool) async {
        guard enabled,["completed","approval","answer"].contains(kind) else{return}
        let fingerprint=[installationID,thread,turn,kind].joined(separator:"\n")
        let id=SHA256.hash(data:Data(fingerprint.utf8)).map{String(format:"%02x",$0)}.joined()
        let event=RelayEvent(id:id,kind:kind,title:shareTitles && !privateMode ? title:"",macName:Host.current().localizedName ?? "Mac",createdAt:Date())
        do{try await relay.send(event);issue=nil}catch{issue=error.localizedDescription}
    }
}
