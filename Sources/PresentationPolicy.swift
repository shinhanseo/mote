import Foundation

struct PresentationPolicy {
    static func resolvedGroup(_ group:Set<String>,by resolved:Set<String>)->Bool {!group.isEmpty && group.isSubset(of:resolved)}
    static func summary(running:Int,waiting:Int,unread:Int,errors:Int)->String {
        var parts=[String]()
        if running>0{parts.append(L10n.text("진행 {0}", [String(describing: running)]))}
        if waiting>0{parts.append(L10n.text("대기 {0}", [String(describing: waiting)]))}
        if unread>0{parts.append(L10n.text("답변 {0}", [String(describing: unread)]))}
        if errors>0{parts.append(L10n.text("오류 {0}", [String(describing: errors)]))}
        return parts.joined(separator:" · ")
    }
    static func isDeferred(thread:String,turn:String,records:[String:String])->Bool {records[thread]==turn}
    static func requestLabel(_ method:String)->String? {
        if method.contains("commandExecution"){return L10n.text("명령 실행 승인이 필요해요")}
        if method.contains("fileChange"){return L10n.text("파일 변경 승인이 필요해요")}
        if method.contains("permissions"){return L10n.text("추가 권한 승인이 필요해요")}
        if method.contains("requestUserInput"){return L10n.text("진행 방식을 골라 주세요")}
        if method.contains("elicitation"){return L10n.text("연결된 도구에서 확인을 요청했어요")}
        return nil
    }
}
