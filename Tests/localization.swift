import Foundation
let suite="dev.local.mote.l10n.tests"
let d=L10n.defaults
for (key,value) in L10n.english {
 let a=Set(key.components(separatedBy:"{").dropFirst().compactMap{$0.components(separatedBy:"}").first})
 let b=Set(value.components(separatedBy:"{").dropFirst().compactMap{$0.components(separatedBy:"}").first})
 precondition(a==b,"Localization arguments differ: \(key)")
}
d.set("en",forKey:"appLanguage")
precondition(L10n.text("진행 {0}",["2"])=="Working 2")
precondition(L10n.text("알림 켜짐")=="Notifications on")
precondition(L10n.text("명령 실행 승인이 필요해요")=="Command approval needed")
d.set("ko",forKey:"appLanguage")
precondition(L10n.text("Notifications on")=="알림 켜짐")
d.removePersistentDomain(forName:ProcessInfo.processInfo.environment["MOTE_TEST_SUITE"]!)
print("PASS: Korean/English switching and translation argument parity")
