import Foundation
import CloudKit

// This schema is shared by the iPhone receiver and the opt-in Mac sender.
// Notifications contain metadata only. Explicit replies use encrypted CloudKit fields.
struct RelayEvent: Identifiable, Codable, Equatable {
    let id:String
    let kind:String
    let title:String
    let macName:String
    let createdAt:Date
    var replyMac:String? = nil
    var replyUntil:Date? = nil
    var canReply:Bool {kind=="answer" && replyMac != nil && (replyUntil ?? .distantPast)>Date()}
    var symbol:String {kind=="approval" ? "hand.raised":kind=="answer" ? "text.bubble":"checkmark"}
    static func decode(_ record:CKRecord)->RelayEvent? {
        guard let kind=record["kind"] as? String,["completed","approval","answer"].contains(kind),let date=record["occurredAt"] as? Date else{return nil}
        return RelayEvent(id:record.recordID.recordName,kind:kind,title:record["title"] as? String ?? "",macName:record["macName"] as? String ?? "Mac",createdAt:date,replyMac:record["replyMac"] as? String,replyUntil:record["replyUntil"] as? Date)
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
            info.titleLocalizationKey="%1$@"
            info.titleLocalizationArgs=["title"]
            info.alertLocalizationKey=kind=="completed" ? "PUSH_COMPLETED":kind=="approval" ? "PUSH_APPROVAL":"PUSH_ANSWER"
            info.soundName="default"
            info.shouldSendContentAvailable=true
            // Only the explicitly shared title; never prompts, commands or thread IDs.
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
        record["kind"]=event.kind as CKRecordValue;record["title"]=(event.title.isEmpty ? "Mote":String(event.title.prefix(100))) as CKRecordValue
        record["macName"]=event.macName as CKRecordValue;record["occurredAt"]=event.createdAt as CKRecordValue
        if let mac=event.replyMac,let until=event.replyUntil {record["replyMac"]=mac as CKRecordValue;record["replyUntil"]=until as CKRecordValue}
        _ = try await db.save(record)
    }
    func queueReply(event:RelayEvent,text:String) async throws -> RelayReply {
        guard event.canReply,let mac=event.replyMac else{throw ReplyCloudError.expired}
        let body=text.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !body.isEmpty,body.count<=4000 else{throw ReplyCloudError.invalid}
        let db=try database(),id=CKRecord.ID(recordName:"reply-"+event.id)
        if let existing=try await reply(eventID:event.id){return existing}
        let r=CKRecord(recordType:"MoteReply",recordID:id)
        r["eventID"]=event.id as CKRecordValue;r["macID"]=mac as CKRecordValue
        r["status"]="queued" as CKRecordValue;r["expiresAt"]=min(event.replyUntil!,Date().addingTimeInterval(120)) as CKRecordValue
        r.encryptedValues["body"]=body as CKRecordValue
        return try RelayReply.decode(await db.save(r))!
    }
    func reply(eventID:String) async throws -> RelayReply? {
        let db=try database()
        do{return RelayReply.decode(try await db.record(for:CKRecord.ID(recordName:"reply-"+eventID)))}catch let e as CKError where e.code == .unknownItem{return nil}
    }
    func queuedReplies(events:[String]) async throws -> [CKRecord] {
        guard !events.isEmpty else{return []}
        let results=try await database().records(for:events.prefix(100).map{CKRecord.ID(recordName:"reply-"+$0)})
        return try results.values.compactMap {result in
            do{let r=try result.get();return ["queued","delivering"].contains(r["status"] as? String ?? "") ? r:nil}
            catch let e as CKError where e.code == .unknownItem{return nil}
        }
    }
    func updateReply(_ record:CKRecord,status:String,message:String="") async throws {
        record["status"]=status as CKRecordValue;record["message"]=message as CKRecordValue
        if status != "queued" && status != "delivering" {record.encryptedValues["body"]=nil}
        _ = try await database().save(record)
    }
}

struct RelayReply:Equatable {
    let id:String
    let eventID:String
    let macID:String
    let body:String
    let status:String
    let expiresAt:Date
    let message:String
    static func decode(_ r:CKRecord)->RelayReply? {
        guard let event=r["eventID"] as? String,let mac=r["macID"] as? String,let status=r["status"] as? String,let expires=r["expiresAt"] as? Date else{return nil}
        return RelayReply(id:r.recordID.recordName,eventID:event,macID:mac,body:r.encryptedValues["body"] as? String ?? "",status:status,expiresAt:expires,message:r["message"] as? String ?? "")
    }
}
enum ReplyCloudError:LocalizedError {
    case expired,invalid
    var errorDescription:String? {self == .expired ? "답변 가능한 시간이 지났어요. Mac에서 확인해 주세요.":"답변을 1~4,000자로 입력해 주세요."}
}
