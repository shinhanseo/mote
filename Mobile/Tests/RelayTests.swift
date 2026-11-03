import Foundation
import CloudKit
@main struct RelayTests {
    static func main() async throws {
        let r=CKRecord(recordType:"MoteEvent",recordID:CKRecord.ID(recordName:"fixture"))
        r["kind"]="completed" as CKRecordValue;r["occurredAt"]=Date() as CKRecordValue
        precondition(RelayEvent.decode(r)?.title=="")
        r["kind"]="unknown" as CKRecordValue;precondition(RelayEvent.decode(r)==nil)
        r["kind"]="approval" as CKRecordValue;precondition(RelayEvent.decode(r)?.symbol=="hand.raised")
        r["kind"]="answer" as CKRecordValue;precondition(RelayEvent.decode(r)?.symbol=="text.bubble")
        let event=RelayEvent.decode(r)!,copy=try JSONDecoder().decode(RelayEvent.self,from:JSONEncoder().encode(event))
        precondition(event==copy)
        do {try await CloudRelay().checkAccount();fatalError("unsigned process must not initialize CloudKit")}
        catch RelayError.notConfigured {} catch {fatalError("unexpected error: \(error)")}
        print("PASS: CloudKit record validation, privacy-safe defaults, persistence and unsigned-build guard")
    }
}
