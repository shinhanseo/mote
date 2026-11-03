import Foundation
let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try! FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
defer{try? FileManager.default.removeItem(at:root)}
let db=root.appendingPathComponent("state_5.sqlite")
try! Data("database".utf8).write(to:db)
let signal=DispatchSemaphore(value:0)
let watcher=RecordWatcher(home:root.path)
watcher.start{signal.signal()}
func expectChange(_ name:String){precondition(signal.wait(timeout:.now()+3) == .success,name)}
func quiet(){while signal.wait(timeout:.now()+0.4) == .success{}}
expectChange("initial database armed");quiet()
let h=try! FileHandle(forWritingTo:db);try! h.seekToEnd();try! h.write(contentsOf:Data("append".utf8));try! h.close()
expectChange("database append detected");quiet()
try! Data("replacement".utf8).write(to:db,options:.atomic)
expectChange("atomic database replacement detected");quiet()
let wal=root.appendingPathComponent("state_5.sqlite-wal")
try! Data("wal".utf8).write(to:wal)
expectChange("new WAL detected");quiet()
let w=try! FileHandle(forWritingTo:wal);try! w.seekToEnd();try! w.write(contentsOf:Data("commit".utf8));try! w.close()
expectChange("WAL write detected");quiet()
try! Data("not a database".utf8).write(to:root.appendingPathComponent("unrelated.log"))
precondition(signal.wait(timeout:.now()+0.6) == .timedOut,"unrelated file must not trigger record read")
let writerDone=DispatchSemaphore(value:0)
DispatchQueue.global().async {
    for _ in 0..<20 {
        if let handle=try? FileHandle(forWritingTo:wal){_ = try? handle.seekToEnd();try? handle.write(contentsOf:Data("x".utf8));try? handle.close()}
        Thread.sleep(forTimeInterval:0.05)
    }
    writerDone.signal()
}
precondition(signal.wait(timeout:.now()+0.8) == .success,"continuous writes must not starve delivery")
precondition(writerDone.wait(timeout:.now()+3) == .success,"fixture writer finished")
quiet()
let next=root.appendingPathComponent("state_6.sqlite")
try! Data("new schema".utf8).write(to:next)
expectChange("new state database selected");quiet()
let obsolete=try! FileHandle(forWritingTo:db);try! obsolete.seekToEnd();try! obsolete.write(contentsOf:Data("old".utf8));try! obsolete.close()
precondition(signal.wait(timeout:.now()+0.6) == .timedOut,"obsolete state database must be unwatched")
watcher.stop()
print("PASS: database writes, atomic replacement, WAL creation/write, unrelated-file filtering, stop")
