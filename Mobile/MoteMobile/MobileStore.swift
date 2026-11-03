import SwiftUI
import UserNotifications
import UIKit

@MainActor final class MobileStore:ObservableObject {
    @Published var events=[RelayEvent]()
    @Published var macs=[RelayMac]()
    @Published var busy=false
    @Published var issue:String?
    @Published var lastSync:Date?
    @Published var notificationStatus="확인 전"
    @Published var selected:RelayEvent?
    @Published var acknowledged:Set<String>
    @Published var snoozed:[String:Date]
    let demo:Bool
    let relay=CloudRelay()
    @AppStorage("notifyCompleted") var completed=true
    @AppStorage("notifyApproval") var approval=true
    @AppStorage("notifyAnswer") var answer=true
    @AppStorage("hideTitles") var hideTitles=true
    var pending:[RelayEvent] {events.filter{!acknowledged.contains($0.id) && (snoozed[$0.id] ?? .distantPast)<=Date()}}
    init(demo:Bool=ProcessInfo.processInfo.arguments.contains("--demo")) {
        self.demo=demo
        acknowledged=demo ? []:Set(UserDefaults.standard.stringArray(forKey:"acknowledged") ?? [])
        snoozed=[:]
        if demo {
            macs=[RelayMac(id:"demo",name:"MacBook Air",lastSeen:Date().addingTimeInterval(-40))]
            events=[RelayEvent(id:"demo-approval",kind:"approval",title:"로그인 화면 다듬기",macName:"MacBook Air",createdAt:Date().addingTimeInterval(-180)),RelayEvent(id:"demo-complete",kind:"completed",title:"모바일 레이아웃 수정",macName:"MacBook Air",createdAt:Date().addingTimeInterval(-720))]
            notificationStatus="미리보기";lastSync=Date()
        } else if let data=UserDefaults.standard.data(forKey:"snoozed"),let decoded=try? JSONDecoder().decode([String:Date].self,from:data){snoozed=decoded}
    }
    func refresh() async {
        guard !demo,!busy else{return};busy=true;defer{busy=false}
        await updatePermission()
        do {
            try await relay.checkAccount()
            let devices=try await relay.macs()
            let found=try await relay.events()
            macs=devices;events=found;lastSync=Date();issue=nil
        }catch{issue=error.localizedDescription}
    }
    func updatePermission() async {
        let settings=await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {case .authorized,.provisional,.ephemeral:notificationStatus="켜짐";case .denied:notificationStatus="꺼짐";default:notificationStatus="허용 필요"}
    }
    func connect() async {
        guard !demo else{return}
        busy=true;defer{busy=false}
        do {
            try await relay.checkAccount()
            let allowed=try await UNUserNotificationCenter.current().requestAuthorization(options:[.alert,.badge,.sound])
            await updatePermission()
            guard allowed else{issue="알림을 받으려면 iPhone 설정에서 Mote 알림을 허용해 주세요.";return}
            var kinds=Set<String>();if completed{kinds.insert("completed")};if approval{kinds.insert("approval")};if answer{kinds.insert("answer")}
            try await relay.subscribe(kinds:kinds)
            UIApplication.shared.registerForRemoteNotifications()
            issue=nil
        }catch{issue=error.localizedDescription}
    }
    func acknowledge(_ event:RelayEvent) {
        acknowledged.insert(event.id)
        if !demo{UserDefaults.standard.set(Array(acknowledged),forKey:"acknowledged")}
        snoozed.removeValue(forKey:event.id)
        if !demo {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers:["snooze-"+event.id])
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers:["snooze-"+event.id])
            if let data=try? JSONEncoder().encode(snoozed){UserDefaults.standard.set(data,forKey:"snoozed")}
        }
    }
    func snooze(_ event:RelayEvent) async {
        let due=Date().addingTimeInterval(600)
        do {
            if !demo {
                let allowed=try await UNUserNotificationCenter.current().requestAuthorization(options:[.alert,.sound])
                guard allowed else{issue="재알림을 받으려면 알림 권한을 허용해 주세요.";return}
                let content=UNMutableNotificationContent();content.title="모트 · 다시 확인해 주세요";content.body="Mac에서 기다리는 작업이 있어요.";content.sound = .default
                content.userInfo=["eventID":event.id]
                try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier:"snooze-"+event.id,content:content,trigger:UNTimeIntervalNotificationTrigger(timeInterval:600,repeats:false)))
            }
            snoozed[event.id]=due
            if !demo,let data=try? JSONEncoder().encode(snoozed){UserDefaults.standard.set(data,forKey:"snoozed")}
        }catch{issue=error.localizedDescription}
    }
    func testNotification() async {
        guard !demo else{return}
        do {
            let allowed=try await UNUserNotificationCenter.current().requestAuthorization(options:[.alert,.sound])
            guard allowed else{issue="설정에서 알림을 허용해 주세요.";return}
            let content=UNMutableNotificationContent();content.title="모트 · 여기까지 잘 도착했어요";content.body="이건 iPhone의 로컬 테스트 알림이에요. Mac 연결 테스트는 아니에요.";content.sound = .default
            try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier:"local-test",content:content,trigger:UNTimeIntervalNotificationTrigger(timeInterval:3,repeats:false)))
        }catch{issue=error.localizedDescription}
    }
    func title(_ event:RelayEvent)->String {hideTitles && !demo ? "Mac에서 확인할 작업":event.title.isEmpty ? "Mac에서 확인할 작업":event.title}
}
final class AppDelegate:NSObject,UIApplicationDelegate,UNUserNotificationCenterDelegate {
    func application(_ application:UIApplication,didFinishLaunchingWithOptions launchOptions:[UIApplication.LaunchOptionsKey:Any]?=nil)->Bool {UNUserNotificationCenter.current().delegate=self;return true}
    func application(_ application:UIApplication,didReceiveRemoteNotification userInfo:[AnyHashable:Any],fetchCompletionHandler completionHandler:@escaping(UIBackgroundFetchResult)->Void){NotificationCenter.default.post(name:.moteRefresh,object:nil);completionHandler(.noData)}
    func userNotificationCenter(_ center:UNUserNotificationCenter,didReceive response:UNNotificationResponse,withCompletionHandler completionHandler:@escaping()->Void){NotificationCenter.default.post(name:.moteRefresh,object:nil);completionHandler()}
    func userNotificationCenter(_ center:UNUserNotificationCenter,willPresent notification:UNNotification,withCompletionHandler completionHandler:@escaping(UNNotificationPresentationOptions)->Void){NotificationCenter.default.post(name:.moteRefresh,object:nil);completionHandler([.banner,.sound])}
}
extension Notification.Name {static let moteRefresh=Notification.Name("moteRefresh")}
