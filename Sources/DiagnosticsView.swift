import SwiftUI
import AppKit

struct DiagnosticsView:View {
    @ObservedObject var model:Monitor
    @ObservedObject var updates:UpdateChecker
    var body:some View {
        VStack(alignment:.leading,spacing:10){
            Text(L10n.text("연결 상태")).font(.headline)
            Label(model.liveIssue ?? (model.liveConnected ? L10n.text("Codex 실시간 연결됨"):L10n.text("Codex 실행 여부를 확인해 주세요. 연결을 다시 시도하고 있어요.")),systemImage:model.liveConnected ? "checkmark.circle":"arrow.clockwise").font(.caption).foregroundStyle(.secondary)
            if let synced=model.lastSync{Text(L10n.text("기록 동기화 · {0}", [String(describing: synced.formatted(date:.omitted,time:.standard))])).font(.caption).foregroundStyle(.secondary)}
            Text(L10n.text("{0}개 대화 감지 · {1}", [String(describing: model.jobs.count), String(describing: model.notificationStatus)])).font(.caption).foregroundStyle(.secondary)
            HStack{Button(L10n.text("다시 확인")){model.refresh();model.updatePermission()};Button(L10n.text("GitHub 열기")){updates.openProject()}}.buttonStyle(.borderless)
            Divider()
            Text("Mote \(updates.version)").font(.headline)
            Text(L10n.text("설정과 작업 상태는 이 Mac에 저장돼요.")).font(.caption).foregroundStyle(.secondary)
            Button(updates.checking ? L10n.text("확인 중…"):L10n.text("업데이트 확인")){updates.check()}.disabled(updates.checking)
            if !updates.message.isEmpty{Text(updates.message).font(.caption).foregroundStyle(.secondary)}
            Text(L10n.text("업데이트 확인 시 공개 GitHub 저장소에만 접속해요. 대화 내용은 보내지 않아요.")).font(.system(size:11)).foregroundStyle(.secondary)
        }
    }
}
