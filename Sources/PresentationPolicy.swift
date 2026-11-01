import Foundation

struct PresentationPolicy {
    static func resolvedGroup(_ group:Set<String>,by resolved:Set<String>)->Bool {!group.isEmpty && group.isSubset(of:resolved)}
    static func summary(running:Int,waiting:Int,unread:Int,errors:Int)->String {
        var parts=[String]()
        if running>0{parts.append("진행 \(running)")}
        if waiting>0{parts.append("대기 \(waiting)")}
        if unread>0{parts.append("답변 \(unread)")}
        if errors>0{parts.append("오류 \(errors)")}
        return parts.joined(separator:" · ")
    }
    static func isDeferred(thread:String,turn:String,records:[String:String])->Bool {records[thread]==turn}
    static func requestLabel(_ method:String)->String? {
        if method.contains("commandExecution"){return "명령 실행 승인이 필요해요"}
        if method.contains("fileChange"){return "파일 변경 승인이 필요해요"}
        if method.contains("permissions"){return "추가 권한 승인이 필요해요"}
        if method.contains("requestUserInput"){return "진행 방식을 골라 주세요"}
        if method.contains("elicitation"){return "연결된 도구에서 확인을 요청했어요"}
        return nil
    }
}
