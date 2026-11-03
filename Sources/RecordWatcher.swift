import Foundation
import Darwin

/// Watches only the two local databases and their WALs, never session contents.
/// Directory events re-arm replaced/rotated files; a periodic fallback remains
/// in Monitor for missed filesystem events or an unavailable directory.
final class RecordWatcher:@unchecked Sendable {
    private let home:String
    private let queue=DispatchQueue(label:"mote.record-events",qos:.utility)
    private struct Watch {let inode:UInt64;let source:DispatchSourceFileSystemObject}
    private var watches=[String:Watch]()
    private var pending=false
    private var change:(@Sendable ()->Void)?
    init(home:String=ProcessInfo.processInfo.environment["CODEX_HOME"] ?? NSHomeDirectory()+"/.codex"){self.home=home}
    deinit{for watch in watches.values{watch.source.cancel()}}
    func start(_ change:@escaping @Sendable ()->Void){queue.async{[weak self] in guard let self else{return};self.change=change;self.rescan()}}
    func rescanEventually(){queue.async{[weak self] in self?.rescan()}}
    func stop(){queue.sync{change=nil;for watch in watches.values{watch.source.cancel()};watches.removeAll()}}
    private func rescan(){
        let names=(try? FileManager.default.contentsOfDirectory(atPath:home)) ?? []
        let state=names.filter{$0.hasPrefix("state_") && $0.hasSuffix(".sqlite")}.sorted{$0.localizedStandardCompare($1) == .orderedDescending}.first
        let databaseNames=[state,"thread_history_1.sqlite"].compactMap{$0}
        let selected=databaseNames.flatMap{[$0,$0+"-wal"]}.filter{names.contains($0)}
        let paths=Set([home]+selected.map{home+"/"+$0})
        for path in Array(watches.keys) where !paths.contains(path){watches.removeValue(forKey:path)?.source.cancel();scheduleChange()}
        for path in paths {
            guard let attrs=try? FileManager.default.attributesOfItem(atPath:path),let inode=attrs[.systemFileNumber] as? UInt64 else{watches.removeValue(forKey:path)?.source.cancel();continue}
            if watches[path]?.inode==inode{continue}
            watches.removeValue(forKey:path)?.source.cancel()
            let fd=open(path,O_EVTONLY|O_CLOEXEC);guard fd>=0 else{continue}
            let source=DispatchSource.makeFileSystemObjectSource(fileDescriptor:fd,eventMask:[.write,.extend,.attrib,.delete,.rename,.revoke],queue:queue)
            source.setCancelHandler{close(fd)}
            source.setEventHandler{[weak self] in
                guard let self else{return}
                if path==self.home {self.rescan()}else{self.scheduleChange()}
            }
            watches[path]=Watch(inode:inode,source:source);source.resume()
            if path != home{scheduleChange()}
        }
    }
    private func scheduleChange(){
        guard !pending else{return};pending=true
        // Bounded leading-edge coalescing: continuous writes cannot postpone it.
        queue.asyncAfter(deadline:.now()+0.25){[weak self] in guard let self else{return};self.pending=false;self.change?()}
    }
}
