import AppKit
import Foundation

struct PublishedRelease {
    let version:String
    let download:URL
    let notes:URL
    static func components(_ value:String)->[Int]? {
        let raw=value.hasPrefix("v") ? String(value.dropFirst()):value
        let parts=raw.split(separator:".",omittingEmptySubsequences:false)
        guard parts.count==3,parts.allSatisfy({!$0.isEmpty && $0.allSatisfy(\.isNumber)}),parts.allSatisfy({Int($0) != nil}) else{return nil}
        return parts.compactMap{Int($0)}
    }
    func isNewer(than current:String)->Bool {
        guard let remote=Self.components(version),let local=Self.components(current) else{return false}
        return local.lexicographicallyPrecedes(remote)
    }
    static func parse(_ data:Data)->PublishedRelease? {
        guard let object=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any],object["draft"] as? Bool != true,object["prerelease"] as? Bool != true,
              let tag=object["tag_name"] as? String,components(tag) != nil else{return nil}
        let version=tag.hasPrefix("v") ? String(tag.dropFirst()):tag
        let expected="https://github.com/shinhanseo/mote/releases/download/v\(version)/Mote-\(version).dmg"
        guard let assets=object["assets"] as? [[String:Any]],assets.contains(where:{$0["browser_download_url"] as? String==expected && $0["state"] as? String=="uploaded"}) else{return nil}
        return PublishedRelease(version:version,download:URL(string:expected)!,notes:URL(string:"https://github.com/shinhanseo/mote/releases/tag/v\(version)")!)
    }
}
@MainActor final class UpdateChecker:ObservableObject {
    let installer=InstallerUpdater()
    func installUpdate(){installer.checkAndInstall()}
    @Published var message=""
    @Published var checking=false
    @Published var available=false
    @Published var release:PublishedRelease?
    @Published var automatic=MotePreferences.store.bool(forKey:"automaticUpdates") {didSet{MotePreferences.store.set(automatic,forKey:"automaticUpdates");if automatic{check()}}}
    private var lastCheck=Date.distantPast
    var version:String {Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? L10n.text("개발 버전")}
    func checkIfNeeded(){if automatic,Date().timeIntervalSince(lastCheck)>6*3600{check()}}
    func check(){
        guard !checking else{return};checking=true;lastCheck=Date();message=L10n.text("배포 버전 확인 중…")
        Task {defer{checking=false}
            do{
                var request=URLRequest(url:URL(string:"https://api.github.com/repos/shinhanseo/mote/releases/latest")!)
                request.setValue("Mote/\(version)",forHTTPHeaderField:"User-Agent");request.setValue("application/vnd.github+json",forHTTPHeaderField:"Accept");request.timeoutInterval=12
                let (data,response)=try await URLSession.shared.data(for:request)
                guard (response as? HTTPURLResponse)?.statusCode==200,let latest=PublishedRelease.parse(data) else{message=L10n.text("지금은 확인할 수 없어요. 잠시 후 다시 시도해 주세요.");return}
                release=latest;available=latest.isNewer(than:version)
                message=available ? L10n.text("새 버전 {0}을 사용할 수 있어요.",[latest.version]):L10n.text("최신 배포 버전을 사용하고 있어요.")
            }catch{message=L10n.text("인터넷 연결을 확인하고 다시 시도해 주세요.")}
        }
    }
    func openDownload(){guard let release else{return};NSWorkspace.shared.open(release.download)}
    func openNotes(){guard let release else{return};NSWorkspace.shared.open(release.notes)}
    func openProject(){NSWorkspace.shared.open(URL(string:"https://github.com/shinhanseo/mote")!)}
}
