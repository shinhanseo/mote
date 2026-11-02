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
