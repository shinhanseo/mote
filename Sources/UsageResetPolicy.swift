import Foundation

struct UsageResetPolicy {
    // Only dates actually observed in the future are eligible. Never replay historical resets.
    var pending:[String:Double]
    var delivered:Set<String>
    mutating func observe(_ snapshot:UsageSnapshot,now:Date){
        for window in snapshot.windows {
            guard let reset=window.reset,reset>now,[300,10080].contains(window.minutes) else{continue}
            pending[String(window.minutes)]=reset.timeIntervalSince1970
        }
    }
    mutating func due(now:Date,short:Bool,weekly:Bool)->[Int]{
        var result=[Int]()
        for (kind,stamp) in pending {
            guard stamp<=now.timeIntervalSince1970 else{continue}
            let key=kind+":"+String(Int(stamp))
            pending.removeValue(forKey:kind)
            guard !delivered.contains(key) else{continue}
            delivered.insert(key)
            guard now.timeIntervalSince1970-stamp<600,let minutes=Int(kind),(minutes==300 ? short:weekly) else{continue}
            result.append(minutes)
        }
        if delivered.count>200{delivered=Set(delivered.sorted().suffix(100))}
        return result.sorted()
    }
}
