import Foundation

/// Follows new conversation turns, not thread updated_at (background completions also update it).
struct CurrentConversationPolicy {
    var started:Double=0
    var turnID:String=""
    mutating func observe(id:String,turn:String,startedAt:Double)->String? {
        guard !turn.isEmpty,startedAt>0 else{return nil}
        guard startedAt>started || (startedAt==started && turn>turnID) else{return nil}
        started=startedAt;turnID=turn;return id
    }
}

struct WorkingConversations {
    static func adding(_ id:String,to ids:[String])->[String] {[id]+ids.filter{$0 != id}}
    static func removing(_ id:String,from ids:[String])->[String] {ids.filter{$0 != id}}
}
