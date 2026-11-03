import Foundation
import CloudKit

// This schema is shared by the iPhone receiver and the opt-in Mac sender.
// It stores notification metadata only. No prompts, replies or command text.
struct RelayEvent: Identifiable, Codable, Equatable {
    let id:String
    let kind:String
    let title:String
    let macName:String
    let createdAt:Date
    var symbol:String {kind=="approval" ? "hand.raised":kind=="answer" ? "text.bubble":"checkmark"}
    static func decode(_ record:CKRecord)->RelayEvent? {
        guard let kind=record["kind"] as? String,["completed","approval","answer"].contains(kind),let date=record["occurredAt"] as? Date else{return nil}
        return RelayEvent(id:record.recordID.recordName,kind:kind,title:record["title"] as? String ?? "",macName:record["macName"] as? String ?? "Mac",createdAt:date)
    }
}
struct RelayMac:Identifiable {
    let id:String
    let name:String
    let lastSeen:Date
}
enum RelayError:LocalizedError {
    case notConfigured,noAccount
    var errorDescription:String? {switch self {case .notConfigured:return "이 빌드에서는 Mac 연결을 사용할 수 없어요.";case .noAccount:return "설정에서 iCloud에 로그인한 뒤 다시 시도해 주세요."}}
}
actor CloudRelay {
    static let containerID="iCloud.im.mote.companion"
    private func database() throws -> CKDatabase {
        guard Bundle.main.object(forInfoDictionaryKey:"MoteCloudKitEnabled") as? Bool == true else{throw RelayError.notConfigured}
        return CKContainer(identifier:Self.containerID).privateCloudDatabase
    }
    func checkAccount() async throws {
        _ = try database()
        guard try await CKContainer(identifier:Self.containerID).accountStatus() == .available else{throw RelayError.noAccount}
    }
    private func records(_ type:String) async throws -> [CKRecord] {
        let db=try database()
        // A bounded, recent query; no polling loop or full-history download.
        let predicate=type=="MoteEvent" ? NSPredicate(format:"occurredAt > %@",Date().addingTimeInterval(-7*86400) as NSDate):NSPredicate(value:true)
        let query=CKQuery(recordType:type,predicate:predicate)
        if type=="MoteEvent" {query.sortDescriptors=[NSSortDescriptor(key:"occurredAt",ascending:false)]}
        let (matches,_)=try await db.records(matching:query,resultsLimit:100)
        // Do not silently turn per-record CloudKit failures into an empty inbox.
        return try matches.map{try $0.1.get()}
    }
    func events() async throws -> [RelayEvent] {try await records("MoteEvent").compactMap(RelayEvent.decode).sorted{$0.createdAt>$1.createdAt}}
    func macs() async throws -> [RelayMac] {try await records("MoteMac").compactMap{record in
        guard let name=record["name"] as? String,let seen=record["lastSeen"] as? Date else{return nil}
        return RelayMac(id:record.recordID.recordName,name:name,lastSeen:seen)
    }}
    func subscribe(kinds:Set<String>) async throws {
        let db=try database()
        for kind in ["completed","approval","answer"] {
            let id="mote-iphone-"+kind
            guard kinds.contains(kind) else {do{_ = try await db.deleteSubscription(withID:id)}catch let e as CKError where e.code == .unknownItem{};continue}
            let subscription=CKQuerySubscription(recordType:"MoteEvent",predicate:NSPredicate(format:"kind == %@",kind),subscriptionID:id,options:.firesOnRecordCreation)
            let info=CKSubscription.NotificationInfo()
            info.title="Mote"
            info.alertLocalizationKey=kind=="completed" ? "PUSH_COMPLETED":kind=="approval" ? "PUSH_APPROVAL":"PUSH_ANSWER"
            info.soundName="default"
            info.shouldSendContentAvailable=true
            // No title, project path, thread ID or actionable Codex approval in the push.
            subscription.notificationInfo=info
            _ = try await db.save(subscription)
        }
    }
    func registerMac(id:String,name:String) async throws {
        let db=try database(),recordID=CKRecord.ID(recordName:"mac-"+id)
        let record:CKRecord
        do{record=try await db.record(for:recordID)}catch let e as CKError where e.code == .unknownItem{record=CKRecord(recordType:"MoteMac",recordID:recordID)}
        record["name"]=name as CKRecordValue;record["lastSeen"]=Date() as CKRecordValue
        _ = try await db.save(record)
    }
    func send(_ event:RelayEvent) async throws {
        let db=try database(),id=CKRecord.ID(recordName:event.id)
        // Repeated sends do not create duplicate notification records.
        do{_ = try await db.record(for:id);return}catch let e as CKError where e.code == .unknownItem{}
        let record=CKRecord(recordType:"MoteEvent",recordID:id)
        record["kind"]=event.kind as CKRecordValue;record["title"]=event.title as CKRecordValue
        record["macName"]=event.macName as CKRecordValue;record["occurredAt"]=event.createdAt as CKRecordValue
        _ = try await db.save(record)
    }
}
