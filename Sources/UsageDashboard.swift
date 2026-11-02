import Foundation
import SwiftUI

struct UsageSnapshot {
    struct Window {
        let used:Double
        let minutes:Int
        let reset:Date?
        var title:String {minutes == 10080 ? "주간 한도":minutes == 300 ? "5시간 한도":"\(minutes)분 한도"}
        var remaining:Int {Int((100-used).rounded())}
        func expired(_ now:Date)->Bool {reset.map{$0<=now} ?? false}
    }
    let recorded:Date
    let windows:[Window]
    static func parse(_ data:Data)->UsageSnapshot? {
        guard let event=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any],
              let stamp=event["timestamp"] as? String,
              let payload=event["payload"] as? [String:Any],
              let limits=payload["rate_limits"] as? [String:Any],
              limits["limit_id"] == nil || limits["limit_id"] as? String == "codex" else{return nil}
        let formatter=ISO8601DateFormatter();formatter.formatOptions=[.withInternetDateTime,.withFractionalSeconds]
        guard let date=formatter.date(from:stamp) ?? ISO8601DateFormatter().date(from:stamp) else{return nil}
        let windows=["primary","secondary"].compactMap { key -> Window? in
            guard let value=limits[key] as? [String:Any],let used=value["used_percent"] as? Double,used.isFinite,(0...100).contains(used),let minutes=value["window_minutes"] as? Int,minutes>0 else{return nil}
            return Window(used:used,minutes:minutes,reset:(value["resets_at"] as? Double).map{Date(timeIntervalSince1970:$0)})
        }
        return windows.isEmpty ? nil:UsageSnapshot(recorded:date,windows:windows)
    }
    static func read()->UsageSnapshot? {
        let home=ProcessInfo.processInfo.environment["CODEX_HOME"] ?? NSHomeDirectory()+"/.codex"
        guard let files=try? FileManager.default.contentsOfDirectory(atPath:home),let state=files.filter({$0.hasPrefix("state_") && $0.hasSuffix(".sqlite")}).sorted(by:{$0.localizedStandardCompare($1) == .orderedDescending}).first,
              let rows=try? LocalReader.query(home+"/"+state,"SELECT rollout_path FROM threads WHERE archived=0 AND agent_path IS NULL ORDER BY updated_at DESC LIMIT 30") else{return nil}
        var newest:UsageSnapshot?
        for row in rows {
            guard let path=row.first,path.hasPrefix(home+"/"),let handle=FileHandle(forReadingAtPath:path) else{continue}
            defer{try? handle.close()}
            guard let end=try? handle.seekToEnd() else{continue}
            try? handle.seek(toOffset:end>1_048_576 ? end-1_048_576:0)
            guard let data=try? handle.readToEnd() else{continue}
            for line in data.split(separator:10).reversed() {
                guard let snapshot=parse(Data(line)) else{continue}
                if newest == nil || snapshot.recorded>newest!.recorded{newest=snapshot}
                break
            }
        }
        return newest
    }
}

struct UsageDashboard:View {
    @ObservedObject var model:Monitor
    var body:some View {
        VStack(alignment:.leading,spacing:12){
            HStack{Label("Codex 사용량",systemImage:"chart.bar").font(.system(size:13,weight:.semibold));Spacer();Button{model.refreshUsage(force:true)}label:{Image(systemName:"arrow.clockwise")}.buttonStyle(.plain).disabled(model.usageLoading).accessibilityLabel("로컬 사용량 기록 다시 읽기")}
            if let snapshot=model.usage {
                ForEach(Array(snapshot.windows.enumerated()),id:\.offset){_,window in
                    VStack(alignment:.leading,spacing:6){
                        HStack{Text(window.title).font(.caption);Spacer();Text(window.expired(Date()) ? "새 기록 대기":"\(window.remaining)% 남음").font(.system(size:12,weight:.semibold)).monospacedDigit()}
                        ProgressView(value:100-window.used,total:100).tint(window.remaining<=20 ? .orange:Palette.olive).opacity(window.expired(Date()) ? 0.3:1)
                        if let reset=window.reset,window.remaining<=20,!window.expired(Date()){TimelineView(.periodic(from:.now,by:60)){context in
                            let minutes=max(0,Int(reset.timeIntervalSince(context.date)/60))
                            Text("초기화까지 \(minutes/60)시간 \(minutes%60)분 · 예정 시각 기준").font(.system(size:12,weight:.medium))
                        }}
                        if let reset=window.reset {Text(window.expired(Date()) ? "초기화 시각 경과 · 최신 사용량은 아직 확인되지 않았어요":"초기화 · \(reset.formatted(date:.abbreviated,time:.shortened))").font(.system(size:10)).foregroundStyle(.secondary)}
                    }
                }
                Text("기록 시각 · \(snapshot.recorded.formatted(date:.abbreviated,time:.shortened))").font(.system(size:10)).foregroundStyle(.secondary)
                if Date().timeIntervalSince(snapshot.recorded)>900 {Text("15분 이상 지난 기록이에요. 실제 잔여량과 다를 수 있어요.").font(.system(size:10)).foregroundStyle(.orange)}
            }else{Text(model.usageLoading ? "로컬 사용량 기록 확인 중…":"사용량 기록이 아직 없어요. Codex에서 작업한 뒤 다시 확인해 주세요.").font(.caption).foregroundStyle(.secondary)}
            Text("이 Mac의 최근 Codex 기록 기준 · 계정 전환 시 이전 계정 기록일 수 있어요. 새로고침은 서버 조회가 아닌 기록 재확인입니다.").font(.system(size:10)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
        }.padding(14).background(Palette.olive.opacity(0.06),in:RoundedRectangle(cornerRadius:14))
    }
}
