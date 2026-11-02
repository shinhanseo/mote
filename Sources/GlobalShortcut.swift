import AppKit
import Carbon

@MainActor final class GlobalShortcut {
    private var reference:EventHotKeyRef?
    private var handler:EventHandlerRef?
    var action:(()->Void)?
    init(){
        var spec=EventTypeSpec(eventClass:OSType(kEventClassKeyboard),eventKind:UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(),{_,_,context in
            guard let context else{return OSStatus(eventNotHandledErr)}
            let shortcut=Unmanaged<GlobalShortcut>.fromOpaque(context).takeUnretainedValue()
            Task{@MainActor in shortcut.action?()};return noErr
        },1,&spec,Unmanaged.passUnretained(self).toOpaque(),&handler)
    }
    func register(_ choice:Int)->Bool {
        if let reference{UnregisterEventHotKey(reference)};reference=nil
        guard choice != 0 else{return true}
        let modifiers=choice==1 ? UInt32(controlKey|optionKey):UInt32(cmdKey|shiftKey)
        return RegisterEventHotKey(UInt32(kVK_Space),modifiers,EventHotKeyID(signature:0x4D4F5445,id:1),GetApplicationEventTarget(),0,&reference)==noErr
    }
    deinit{if let reference{UnregisterEventHotKey(reference)};if let handler{RemoveEventHandler(handler)}}
}
