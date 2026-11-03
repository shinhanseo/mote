import SwiftUI
import AppKit

struct DiagnosticsView:View {
    @ObservedObject var model:Monitor
    @ObservedObject var updates:UpdateChecker
    var body:some View {
        VStack(alignment:.leading,spacing:10){
            Text(L10n.text("연결 상태")).font(.headline)
            Label(model.liveIssue ?? (model.liveConnected ? L10n.text("Codex 실시간 연결됨"):L10n.text("Codex 실행 여부를 확인해 주세요. 연결을 다시 시도하고 있어요.")),systemImage:model.liveConnected ? "checkmark.circle":"arrow.clockwise").font(.caption).foregroundStyle(.secondary)
            if let synced=model.lastSync{Text(L10n.text("기록 동기화 · {0}", [String(describing: synced.moteFormatted(date:.omitted,time:.standard))])).font(.caption).foregroundStyle(.secondary)}
            Text(L10n.text("{0}개 대화 감지 · {1}", [String(describing: model.jobs.count), String(describing: model.notificationStatus)])).font(.caption).foregroundStyle(.secondary)
            HStack{Button(L10n.text("다시 확인")){model.refresh();model.updatePermission()};Button(L10n.text("GitHub 열기")){updates.openProject()}}.buttonStyle(.borderless)
            if let error=model.error {Text(error).font(.caption).foregroundStyle(.orange)}
            Button(L10n.text("진단 정보 복사")){
                let summary=LocalReader.diagnosticSummary()
                NSPasteboard.general.clearContents();NSPasteboard.general.setString(summary,forType:.string)
            }
            Text(L10n.text("진단 정보에는 기록 구조만 포함되며 대화 내용과 제목은 포함되지 않아요.")).font(.caption).foregroundStyle(.secondary)
            Divider()
            MobileRelaySettings(mobile:model.mobile)
            Divider()
            Text("Mote \(updates.version)").font(.headline)
            Text(L10n.text("설정과 작업 상태는 이 Mac에 저장돼요.")).font(.caption).foregroundStyle(.secondary)
            Button(L10n.text("업데이트 확인 및 설치")){updates.installUpdate()}
            Button(updates.checking ? L10n.text("확인 중…"):L10n.text("업데이트 확인")){updates.check()}.disabled(updates.checking)
            Toggle(L10n.text("새 배포 버전 자동 확인"),isOn:$updates.automatic)
            if updates.available {
                HStack{Button(L10n.text("앱에서 업데이트")){updates.installUpdate()};Button(L10n.text("변경 내용")){updates.openNotes()}}
                Text(L10n.text("서명된 업데이트를 내려받아 설치하고 Mote를 다시 실행해요. 설치 전 확인 창이 표시됩니다.")).font(.caption).foregroundStyle(.secondary)
            }
            if !updates.message.isEmpty{Text(L10n.text(updates.message)).font(.caption).foregroundStyle(.secondary)}
            Text(L10n.text("업데이트 확인은 GitHub 공개 릴리스에만 접속해요. 자동 확인을 켜면 실행 중 6시간마다 확인하며, 대화 내용은 보내지 않아요.")).font(.system(size:11)).foregroundStyle(.secondary)
        }
    }
}

struct MobileRelaySettings:View {
    @ObservedObject var mobile:MobileNotifier
    var body:some View {
        VStack(alignment:.leading,spacing:10){
            Text("아이폰 알림").font(.headline)
            Text("같은 iCloud 계정의 아이폰으로 완료·승인·입력 필요 알림을 보내요. 대화 제목은 기본적으로 보내지 않아요.").font(.caption).foregroundStyle(.secondary)
            if mobile.enabled {
                Label("iCloud 전송 켜짐",systemImage:"iphone")
                Toggle("Mac 잠금·자리 비움 때만 보내기",isOn:$mobile.awayOnly)
                Text("Mac을 사용하는 동안은 Mac에서만 알려요. 잠그거나 5분간 입력이 없으면 새 작업 알림을 아이폰으로 보내요.").font(.caption).foregroundStyle(.secondary)
                Toggle("아이폰에서 답변 보내기",isOn:$mobile.remoteReplies)
                Text("입력 필요 알림에서 일반 답변을 보낼 수 있어요. 답변은 개인 iCloud에 암호화해 전달하고, Mac이 켜져 있어야 해요. 승인은 Mac에서만 해요.").font(.caption).foregroundStyle(.secondary)
                Toggle("대화 제목도 보내기",isOn:$mobile.shareTitles)
                HStack{Button("아이폰에 테스트 알림"){Task{await mobile.test()}};Button("연결 끄기"){mobile.disconnect()}}
            }else{Button("아이폰 알림 연결"){Task{await mobile.connect()}}}
            if let issue=mobile.issue{Text(issue).font(.caption).foregroundStyle(.orange)}
        }
    }
}
