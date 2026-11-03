import SwiftUI

@main struct MoteMobileApp:App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject var store=MobileStore()
    @AppStorage("appearance") var appearance="light"
    @Environment(\.scenePhase) var phase
    var body:some Scene {
        WindowGroup {
            RootView().environmentObject(store)
                .preferredColorScheme(appearance=="system" ? nil:appearance=="dark" ? .dark:.light)
                .task{await store.refresh()}
                .onChange(of:phase){_,new in if new == .active{Task{await store.refresh()}}}
                .onReceive(NotificationCenter.default.publisher(for:.moteRefresh)){_ in Task{await store.refresh()}}
        }
    }
}
enum Ink {
    static let paper=Color(uiColor:UIColor{traits in traits.userInterfaceStyle == .dark ? UIColor(red:0.10,green:0.11,blue:0.10,alpha:1):UIColor(red:0.975,green:0.973,blue:0.95,alpha:1)})
    static let olive=Color(uiColor:UIColor{traits in traits.userInterfaceStyle == .dark ? UIColor(red:0.73,green:0.77,blue:0.60,alpha:1):UIColor(red:0.37,green:0.42,blue:0.29,alpha:1)})
    static let line=Color.primary.opacity(0.12)
    static func tint(_ kind:String)->Color {kind=="approval" ? Color(uiColor:.systemBrown):kind=="answer" ? Color(uiColor:.systemTeal):olive}
}
struct RootView:View {
    @EnvironmentObject var store:MobileStore
    @State private var tab:Int = {
        let args=ProcessInfo.processInfo.arguments
        return args.contains("--history") ? 1:args.contains("--settings") ? 2:0
    }()
    var body:some View {
        TabView(selection:$tab){
            NavigationStack{NowView()}.tabItem{Label("지금",systemImage:"sparkle")}.tag(0)
            NavigationStack{HistoryView()}.tabItem{Label("기록",systemImage:"clock")}.tag(1)
            NavigationStack{SettingsView()}.tabItem{Label("설정",systemImage:"slider.horizontal.3")}.tag(2)
        }.tint(Ink.olive)
        .sheet(item:$store.selected){event in DetailView(event:event).environmentObject(store).presentationDragIndicator(.visible)}
    }
}
struct Page<Content:View>:View {
    @ViewBuilder var content:Content
    var body:some View {ScrollView{VStack(alignment:.leading,spacing:0){content}.frame(maxWidth:560,alignment:.leading).padding(.horizontal,26).padding(.bottom,32).frame(maxWidth:.infinity)}.background(Ink.paper).toolbarBackground(Ink.paper,for:.navigationBar)}
}
struct BrandHeader:View {
    @EnvironmentObject var store:MobileStore
    var body:some View {
        HStack(alignment:.firstTextBaseline){Text("mote.").font(.system(size:33,weight:.semibold,design:.rounded)).tracking(-1.6);Spacer();Text(store.demo ? "미리보기 · 예시 데이터":store.macs.isEmpty ? "아직 연결 전":"iCloud 연동").font(.caption).foregroundStyle(.secondary)}.padding(.top,18)
    }
}
struct NowView:View {
    @EnvironmentObject var store:MobileStore
    var body:some View {
        Page {
            BrandHeader()
            Text("작은 먼지가, 여기까지.").font(.system(size:13)).foregroundStyle(.secondary).padding(.top,32)
            HStack(alignment:.center,spacing:0){
                VStack(alignment:.leading,spacing:14){
                    Text(store.macs.isEmpty ? "자리를 비워도,\n놓치지 않도록.":store.pending.isEmpty ? "맡긴 일은\n잘 지켜볼게요.":"Mac에서\n소식이 왔어요.")
                        .font(.system(size:34,weight:.semibold)).tracking(-1.8).lineSpacing(5).fixedSize(horizontal:false,vertical:true)
                }.frame(maxWidth:.infinity,alignment:.leading)
                DustView(sleeping:store.macs.isEmpty || store.pending.isEmpty).frame(width:106,height:100).padding(.trailing,-12)
            }.padding(.top,14).padding(.bottom,29)
            if store.macs.isEmpty {
                Rectangle().fill(Ink.line).frame(height:1)
                Text("Mac에 맡긴 일이 끝나거나,\n내 확인이 필요할 때 알려드려요.").font(.system(size:16)).foregroundStyle(.secondary).lineSpacing(6).padding(.top,24)
                Button{Task{await store.connect();await store.refresh()}}label:{HStack{Text(store.busy ? "확인하고 있어요":"내 Mac 연결하기");Spacer();if store.busy{ProgressView()}else{Image(systemName:"arrow.right")}}.font(.system(size:16,weight:.medium)).padding(.vertical,18)}.disabled(store.busy).padding(.top,16)
                Text("같은 iCloud 계정을 사용해요.\n별도 Mote 계정은 필요 없어요.").font(.system(size:12)).foregroundStyle(.secondary).lineSpacing(5).padding(.top,3)
            }else{
                HStack{Text("도착한 소식").font(.system(size:14,weight:.semibold));Text("\(store.pending.count)").font(.system(size:14,weight:.medium)).foregroundStyle(Ink.olive);Spacer();Text("최근 7일").font(.caption).foregroundStyle(.secondary)}.padding(.bottom,16)
                Rectangle().fill(Ink.line).frame(height:1)
                TimelineView(.periodic(from:.now,by:60)){_ in
                    if store.pending.isEmpty {Text("아직 새 소식은 없어요.").foregroundStyle(.secondary).padding(.vertical,30)}
                    ForEach(store.pending){event in EventRow(event:event)}
                }
                HStack(spacing:8){Image(systemName:"laptopcomputer");Text(store.macs.first?.name ?? "Mac");Spacer();if let date=store.lastSync{Text("수신 ")+Text(date,style:.relative)}}.font(.system(size:12)).foregroundStyle(.secondary).padding(.top,27)
                Text("Mac의 마지막 소식 기준이에요. 지금 상태와 다를 수 있어요.").font(.system(size:11)).foregroundStyle(.secondary).padding(.top,8)
            }
            if let issue=store.issue {IssueNote(text:issue).padding(.top,24)}
            Spacer(minLength:35)
            HStack{Text("멀리 있어도, 가볍게.");Spacer();Text("mote for iPhone")}.font(.system(size:11)).foregroundStyle(.secondary).padding(.top,20)
        }.toolbar(.hidden,for:.navigationBar).refreshable{await store.refresh()}
    }
}
struct EventRow:View {
    @EnvironmentObject var store:MobileStore
    let event:RelayEvent
    var body:some View {
        Button{store.selected=event}label:{
            HStack(alignment:.top,spacing:14){
                Image(systemName:event.symbol).font(.system(size:19,weight:.regular)).foregroundStyle(Ink.tint(event.kind)).frame(width:24).padding(.top,3)
                VStack(alignment:.leading,spacing:9){
                    Text(event.kind=="approval" ? "승인이 필요해요":event.kind=="answer" ? "답변을 기다려요":"작업이 끝났어요").font(.system(size:17,weight:.medium)).foregroundStyle(.primary)
                    Text(store.title(event)).font(.system(size:14)).foregroundStyle(.secondary).lineLimit(2)
                    HStack(spacing:5){Text(event.macName);Text("·");Text(event.createdAt,style:.relative);if store.acknowledged.contains(event.id){Text("· 확인함")}}.font(.system(size:11)).foregroundStyle(.secondary)
                }.frame(maxWidth:.infinity,alignment:.leading)
                Image(systemName:"chevron.right").font(.system(size:11,weight:.medium)).foregroundStyle(.tertiary).padding(.top,5)
            }.padding(.vertical,22).contentShape(Rectangle())
        }.buttonStyle(.plain)
        Rectangle().fill(Ink.line).frame(height:1)
    }
}
struct HistoryView:View {
    @EnvironmentObject var store:MobileStore
    var body:some View {
        Page {
            Text("남겨둔 소식").font(.system(size:32,weight:.semibold)).tracking(-1.5).padding(.top,25)
            Text("최근 7일 동안 도착한 알림이에요.\n진행 상황의 실시간 목록은 아니에요.").font(.system(size:14)).foregroundStyle(.secondary).lineSpacing(5).padding(.top,12).padding(.bottom,30)
            if store.events.isEmpty {DustView(sleeping:true).frame(width:125,height:110).frame(maxWidth:.infinity).padding(.top,50);Text("첫 소식이 오면 여기에 남겨둘게요.").font(.system(size:14)).foregroundStyle(.secondary).frame(maxWidth:.infinity).padding(.top,15)}
            ForEach(store.events){event in EventRow(event:event)}
            if let issue=store.issue{IssueNote(text:issue).padding(.top,20)}
        }.toolbar(.hidden,for:.navigationBar).refreshable{await store.refresh()}
    }
}
struct SettingsView:View {
    @EnvironmentObject var store:MobileStore
    @State private var preview=false
    @AppStorage("appearance") var appearance="light"
    var body:some View {
        Page {
            Text("나에게 맞게").font(.system(size:32,weight:.semibold)).tracking(-1.5).padding(.top,25).padding(.bottom,34)
            caption("화면")
            Picker("화면 모드",selection:$appearance){Text("화이트").tag("light");Text("다크").tag("dark");Text("시스템").tag("system")}.pickerStyle(.segmented).padding(.vertical,20)
            caption("연결")
            if store.macs.isEmpty {Text("연결된 Mac이 없어요").font(.system(size:16)).padding(.vertical,20)}
            ForEach(store.macs){mac in HStack{Image(systemName:"laptopcomputer");Text(mac.name);Spacer()}.padding(.vertical,20)}
            Button("iCloud 연결 확인"){Task{await store.connect();await store.refresh()}}.padding(.bottom,23).disabled(store.busy)
            caption("받고 싶은 소식")
            Toggle("작업 완료",isOn:$store.completed).padding(.top,18)
            Toggle("승인 필요",isOn:$store.approval).padding(.top,16)
            Toggle("입력 필요",isOn:$store.answer).padding(.top,16)
            Button("알림 선택 적용"){Task{await store.connect()}}.padding(.top,18).padding(.bottom,30).disabled(store.busy)
            caption("개인정보")
            Toggle("앱에서 대화 제목 숨기기",isOn:$store.hideTitles).padding(.top,18)
            Text("푸시 제목은 Mac Mote의 ‘대화 제목도 보내기’ 설정을 따라요. 이 스위치는 iPhone 앱 안에서만 제목을 숨겨요.").font(.system(size:12)).foregroundStyle(.secondary).lineSpacing(5).padding(.top,10).padding(.bottom,28)
            caption("알림 확인")
            HStack{Text("iPhone 알림");Spacer();Text(store.notificationStatus).foregroundStyle(.secondary)}.padding(.top,18)
            Button("iPhone에서 테스트 알림 받기"){Task{await store.testNotification()}}.padding(.top,20)
            Text("3초 뒤 이 기기에 알림을 표시해요. Mac 연동 테스트와는 별개예요.").font(.system(size:12)).foregroundStyle(.secondary).lineSpacing(5).padding(.top,8)
            Button("iPhone 알림 설정 열기"){if let url=URL(string:UIApplication.openSettingsURLString){UIApplication.shared.open(url)}}.padding(.top,18)
            if let issue=store.issue{IssueNote(text:issue).padding(.top,24)}
            if !store.demo {Button("디자인 미리보기"){preview=true}.padding(.top,24)}
            Text("Mote for iPhone · 개발 중\nCloudKit을 사용하며 별도 운영 서버는 없어요.\n승인과 답변을 대신 전송하지 않아요.").font(.system(size:12)).foregroundStyle(.secondary).lineSpacing(6).padding(.top,38)
        }.toolbar(.hidden,for:.navigationBar)
        .fullScreenCover(isPresented:$preview){PreviewScreen()}
    }
    func caption(_ text:String)->some View {VStack(alignment:.leading,spacing:12){Text(text).font(.system(size:12,weight:.medium)).foregroundStyle(Ink.olive);Rectangle().fill(Ink.line).frame(height:1)}}
}
struct DetailView:View {
    @EnvironmentObject var store:MobileStore
    @Environment(\.dismiss) var dismiss
    let event:RelayEvent
    var body:some View {
        NavigationStack{Page{
            DustView().frame(width:110,height:95).padding(.top,25)
            Text(event.kind=="completed" ? "잘 끝났대요.":"확인을 기다려요.").font(.system(size:32,weight:.semibold)).tracking(-1.2).padding(.top,20)
            Text(store.title(event)).font(.system(size:19)).padding(.top,17)
            Text(event.macName+" · "+event.createdAt.formatted(date:.abbreviated,time:.shortened)).font(.caption).foregroundStyle(.secondary).padding(.top,12)
            Rectangle().fill(Ink.line).frame(height:1).padding(.vertical,25)
            Text("알림이 도착한 시점의 상태예요.\n정확한 진행 상황과 승인·답변은 Mac의 Codex에서 확인해 주세요.").font(.system(size:15)).foregroundStyle(.secondary).lineSpacing(6)
            Button("이 iPhone에서 확인했어요"){store.acknowledge(event);dismiss()}.buttonStyle(.borderedProminent).controlSize(.large).padding(.top,30)
            Button("10분 뒤 다시 알려줘요"){Task{await store.snooze(event);dismiss()}}.padding(.top,18)
            Text("확인 표시는 이 iPhone에만 저장돼요. Mac의 읽음 상태나 Codex 작업은 바뀌지 않아요.").font(.system(size:12)).foregroundStyle(.secondary).lineSpacing(5).padding(.top,20)
        }.toolbar{ToolbarItem(placement:.topBarTrailing){Button("닫기"){dismiss()}}}}
    }
}
struct IssueNote:View {
    let text:String
    var body:some View {HStack(alignment:.top,spacing:9){Image(systemName:"info.circle");Text(text).fixedSize(horizontal:false,vertical:true)}.font(.system(size:12)).foregroundStyle(.secondary).lineSpacing(4)}
}

struct PreviewScreen:View {
    @StateObject private var preview=MobileStore(demo:true)
    @Environment(\.dismiss) private var dismiss
    var body:some View {
        VStack(spacing:0){
            HStack{Text("예시 데이터 · 실제 작업이 아니에요").font(.caption).foregroundStyle(.secondary);Spacer();Button("미리보기 닫기"){dismiss()}}.padding(.horizontal,20).padding(.top,12).padding(.bottom,8).background(Ink.paper)
            RootView().environmentObject(preview)
        }
    }
}
