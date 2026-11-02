import AppKit
import Foundation

@MainActor final class UpdateChecker:ObservableObject {
    @Published var message=""
    @Published var checking=false
    @Published var available=false
    var version:String {Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? L10n.text("개발 버전")}
    var revision:String {Bundle.main.object(forInfoDictionaryKey:"MoteSourceRevision") as? String ?? ""}
    func check(){
        guard !checking else{return};checking=true;message=L10n.text("GitHub 최신 버전 확인 중…")
        Task {defer{checking=false}
            do{
                var request=URLRequest(url:URL(string:"https://api.github.com/repos/shinhanseo/mote/commits/main")!)
                request.setValue("Mote/\(version)",forHTTPHeaderField:"User-Agent");request.timeoutInterval=12
                let (data,response)=try await URLSession.shared.data(for:request)
                guard (response as? HTTPURLResponse)?.statusCode==200,let object=try JSONSerialization.jsonObject(with:data) as? [String:Any],let sha=object["sha"] as? String else{message=L10n.text("지금은 확인할 수 없어요. 잠시 후 다시 시도해 주세요.");return}
                available=revision.isEmpty || !sha.hasPrefix(revision)
                message=available ? L10n.text("새 소스가 있어요. GitHub에서 업데이트할 수 있어요."):L10n.text("최신 소스 빌드를 사용하고 있어요.")
            }catch{message=L10n.text("인터넷 연결을 확인하고 다시 시도해 주세요.")}
        }
    }
    func openProject(){NSWorkspace.shared.open(URL(string:"https://github.com/shinhanseo/mote")!)}
}
