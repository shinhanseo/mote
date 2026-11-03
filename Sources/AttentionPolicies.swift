import Foundation

struct UsageThresholdPolicy {
    var sent:Set<String>
    mutating func observe(_ snapshot:UsageSnapshot,now:Date)->[(Int,Int)] {
        guard now.timeIntervalSince(snapshot.recorded)>=0,now.timeIntervalSince(snapshot.recorded)<900 else{return []}
        var notices=[(Int,Int)]()
        for window in snapshot.windows {
            guard let reset=window.reset,reset>now else{continue}
            let crossed=[20,5].filter{window.remaining <= $0}
            for threshold in crossed {
                let key="\(window.minutes):\(Int(reset.timeIntervalSince1970)):\(threshold)"
                if sent.insert(key).inserted,threshold==crossed.last {notices.append((window.minutes,threshold))}
            }
        }
        if sent.count>500{sent=Set(sent.sorted().suffix(300))}
        return notices
    }
}
struct SnoozedNotice {
    let jobs:[Job]
    let due:Date
    func unresolved(in current:[Job])->[Job]{jobs.compactMap{old in current.first{$0.id==old.id && $0.turn==old.turn && $0.status==old.status && $0.attentionKey==old.attentionKey && ["approval","answer","unread","failed"].contains($0.status)}}}
}

/// A notice remains relevant only to the turn/request that produced it.
struct NoticeReference:Equatable {
    let job:Job
    func isRelevant(in jobs:[Job])->Bool {
        guard let current=jobs.first(where:{$0.id==job.id && $0.turn==job.turn}) else{return false}
        if job.status=="completed" || job.status=="unread" {
            return ["completed","unread"].contains(current.status) && current.readReceipt != false
        }
        return current.status==job.status && current.attentionKey==job.attentionKey && ["approval","answer","failed"].contains(current.status)
    }
}
