import Foundation
import CloudKit

// Run only in a provisioned Development helper; never on startup in production.
@main struct PrepareReplySchema {
 static func main() async {
  do {
   guard Bundle.main.object(forInfoDictionaryKey:"MoteSchemaPreparation") as? Bool == true else{fatalError("Schema helper only")}
   let db=CKContainer(identifier:CloudRelay.containerID).privateCloudDatabase
   let event=CKRecord(recordType:"MoteEvent",recordID:CKRecord.ID(recordName:"reply-schema-event"))
   event["kind"]="answer" as CKRecordValue;event["title"]="Schema test" as CKRecordValue;event["macName"]="Schema test" as CKRecordValue;event["occurredAt"]=Date() as CKRecordValue
   event["replyMac"]="schema-test" as CKRecordValue;event["replyUntil"]=Date() as CKRecordValue
   _ = try await db.save(event)
   let reply=CKRecord(recordType:"MoteReply",recordID:CKRecord.ID(recordName:"reply-schema-command"))
   reply["eventID"]="reply-schema-event" as CKRecordValue;reply["macID"]="schema-test" as CKRecordValue;reply["status"]="queued" as CKRecordValue;reply["message"]="Schema test" as CKRecordValue;reply["expiresAt"]=Date() as CKRecordValue;reply.encryptedValues["body"]="Schema test" as CKRecordValue
   _ = try await db.save(reply)
   _ = try await db.deleteRecord(withID:event.recordID);_ = try await db.deleteRecord(withID:reply.recordID)
   print("PASS: reply fields prepared and test records removed")
  }catch{print("Schema preparation failed: \(error.localizedDescription)");exit(1)}
 }
}
