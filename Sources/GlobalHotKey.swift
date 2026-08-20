import Foundation
import Carbon.HIToolbox

final class GlobalHotKey {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var action: (() -> Void)?

    deinit { unregister() }

    func registerOptionSpace(action: @escaping () -> Void) -> String? {
        unregister()
        self.action = action
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let pointer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return OSStatus(eventNotHandledErr) }
            let owner = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { owner.action?() }
            return noErr
        }, 1, &eventType, pointer, &handler)
        guard status == noErr else { return "全局快捷键事件处理器注册失败（\(status)）" }
        let signature = OSType(0x44534851) // DSHQ
        let identifier = EventHotKeyID(signature: signature, id: 1)
        let registerStatus = RegisterEventHotKey(UInt32(kVK_Space), UInt32(optionKey), identifier,
                                                 GetApplicationEventTarget(), 0, &hotKey)
        guard registerStatus == noErr else {
            unregister()
            return "⌥Space 已被其他应用占用（\(registerStatus)）"
        }
        return nil
    }

    func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
        hotKey = nil
        handler = nil
        action = nil
    }
}
