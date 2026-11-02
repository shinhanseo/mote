import Foundation
import SwiftUI

struct UsageSnapshot {
    struct Window {
        let used:Double
        let minutes:Int
        let reset:Date?
        var title:String {minutes == 10080 ? L10n.text("주간 한도"):minutes == 300 ? L10n.text("5시간 한도"):L10n.text("{0}분 한도", [String(describing: minutes)])}
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
            guard let path=row.first,path.hasPrefix(home+"/"),let snapshot=readFile(path) else{continue}
            if newest == nil || snapshot.recorded>newest!.recorded{newest=snapshot}
        }
        return newest
    }
    private final class FileCache:@unchecked Sendable {
        struct Entry {let size:UInt64;let modified:Date;let inode:UInt64;let snapshot:UsageSnapshot?}
        let lock=NSLock()
        var entries=[String:Entry]()
    }
    private static let cache=FileCache()
    static func readFile(_ path:String)->UsageSnapshot? {
        guard let attrs=try? FileManager.default.attributesOfItem(atPath:path),
              let size=attrs[.size] as? UInt64,let modified=attrs[.modificationDate] as? Date,
              let inode=attrs[.systemFileNumber] as? UInt64 else{return nil}
        cache.lock.lock();let previous=cache.entries[path];cache.lock.unlock()
        if let previous,previous.size==size,previous.modified==modified,previous.inode==inode{return previous.snapshot}
        guard let handle=FileHandle(forReadingAtPath:path) else{return nil}
        defer{try? handle.close()}
        guard let end=try? handle.seekToEnd() else{return nil}
        try? handle.seek(toOffset:end>1_048_576 ? end-1_048_576:0)
        guard let data=try? handle.readToEnd() else{return nil}
        var newest:UsageSnapshot?
        let marker=Data("\"rate_limits\"".utf8)
        for line in data.split(separator:10).reversed() {
            // Most lines are tool/chat text. Decode only quota candidates.
            guard line.range(of:marker) != nil,let snapshot=parse(Data(line)) else{continue}
            newest=snapshot;break
        }
        cache.lock.lock()
        if cache.entries.count>=64,cache.entries[path]==nil {cache.entries.removeAll(keepingCapacity:true)}
        // Store the pre-read stamp: an append during this read invalidates next time.
        cache.entries[path]=FileCache.Entry(size:size,modified:modified,inode:inode,snapshot:newest)
        cache.lock.unlock()
        return newest
    }

}

struct UsageDashboard:View {
    @ObservedObject var model:Monitor
    var body:some View {
        VStack(alignment:.leading,spacing:12){
            HStack{Label(L10n.text("Codex 사용량"),systemImage:"chart.bar").font(.system(size:13,weight:.semibold));Spacer();Button{model.refreshUsage(force:true)}label:{Image(systemName:"arrow.clockwise")}.buttonStyle(.plain).disabled(model.usageLoading).accessibilityLabel(L10n.text("로컬 사용량 기록 다시 읽기"))}
            if let snapshot=model.usage {
                ForEach(Array(snapshot.windows.enumerated()),id:\.offset){_,window in
                    VStack(alignment:.leading,spacing:6){
                        HStack{Text(window.title).font(.caption);Spacer();Text(window.expired(Date()) ? L10n.text("새 기록 대기"):L10n.text("{0}% 남음", [String(describing: window.remaining)])).font(.system(size:12,weight:.semibold)).monospacedDigit()}
                        ProgressView(value:100-window.used,total:100).tint(window.remaining<=20 ? .orange:Palette.olive).opacity(window.expired(Date()) ? 0.3:1)
                        if let reset=window.reset,window.remaining<=20,!window.expired(Date()){TimelineView(.periodic(from:.now,by:60)){context in
                            let minutes=max(0,Int(reset.timeIntervalSince(context.date)/60))
                            Text(L10n.text("초기화까지 {0}시간 {1}분 · 예정 시각 기준", [String(describing: minutes/60), String(describing: minutes%60)])).font(.system(size:12,weight:.medium))
                        }}
                        if let reset=window.reset {Text(window.expired(Date()) ? L10n.text("초기화 시각 경과 · 최신 사용량은 아직 확인되지 않았어요"):L10n.text("초기화 · {0}", [String(describing: reset.moteFormatted(date:.abbreviated,time:.shortened))])).font(.system(size:10)).foregroundStyle(.secondary)}
                    }
                }
                Text(L10n.text("기록 시각 · {0}", [String(describing: snapshot.recorded.moteFormatted(date:.abbreviated,time:.shortened))])).font(.system(size:10)).foregroundStyle(.secondary)
                if Date().timeIntervalSince(snapshot.recorded)>900 {Text(L10n.text("15분 이상 지난 기록이에요. 실제 잔여량과 다를 수 있어요.")).font(.system(size:10)).foregroundStyle(.orange)}
            }else{Text(model.usageLoading ? L10n.text("로컬 사용량 기록 확인 중…"):L10n.text("사용량 기록이 아직 없어요. Codex에서 작업한 뒤 다시 확인해 주세요.")).font(.caption).foregroundStyle(.secondary)}
            Text(L10n.text("이 Mac의 최근 Codex 기록 기준 · 계정 전환 시 이전 계정 기록일 수 있어요. 새로고침은 서버 조회가 아닌 기록 재확인입니다.")).font(.system(size:10)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
        }.padding(14).background(Palette.olive.opacity(0.06),in:RoundedRectangle(cornerRadius:14))
    }
}
