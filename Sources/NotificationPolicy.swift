import Foundation

struct NotificationLedger {
    private(set) var sent:[String:Double]
    init(sent:[String:Double]=[:],now:Date=Date()) {
        self.sent=sent.filter{now.timeIntervalSince1970-$0.value<7*86400}
    }
    mutating func claim(_ key:String,now:Date=Date())->Bool {
        guard sent[key]==nil else{return false}
        sent[key]=now.timeIntervalSince1970
        if sent.count>2000 {sent=Dictionary(uniqueKeysWithValues:sent.sorted{$0.value>$1.value}.prefix(1500).map{($0.key,$0.value)})}
        return true
    }
    static func key(thread:String,turn:String,kind:String,requests:[String]=[])->String {
        [thread,turn,kind,requests.sorted().joined(separator:",")].joined(separator:"|")
    }
}
