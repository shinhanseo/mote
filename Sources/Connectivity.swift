import Network

final class Connectivity: @unchecked Sendable {
    private let monitor=NWPathMonitor()
    func start(_ changed:@escaping @Sendable(Bool)->Void){
        monitor.pathUpdateHandler={path in changed(path.status == .satisfied)}
        monitor.start(queue:DispatchQueue(label:"mote.network",qos:.utility))
    }
    deinit{monitor.cancel()}
}
