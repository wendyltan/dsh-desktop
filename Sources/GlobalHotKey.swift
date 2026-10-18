import Foundation
import Carbon.HIToolbox

/// 一个可配置的全局快捷键（Carbon 虚拟键码 + Carbon 修饰键）。
struct Shortcut: Codable, Hashable {
    var keyCode: UInt32
    var modifiers: UInt32

    static let quickPromptDefault = Shortcut(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey))
    static let guardianDefault = Shortcut(keyCode: UInt32(kVK_ANSI_S), modifiers: UInt32(optionKey))

    /// 人类可读显示，如 ⌥Space、⌥S。
    var displayString: String {
        var parts: [String] = []
        if modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if modifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
        if modifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
        if modifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }
        parts.append(Self.keyLabel(keyCode))
        return parts.joined()
    }

    /// 是否仅为修饰键（不能作为快捷键主键）。
    var isModifierOnly: Bool { keyCode >= 55 && keyCode <= 63 }

    static func keyLabel(_ keyCode: UInt32) -> String {
        let letters: [UInt32: String] = [
            0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F", 5: "G", 4: "H",
            34: "I", 38: "J", 40: "K", 37: "L", 46: "M", 45: "N", 31: "O", 35: "P",
            12: "Q", 15: "R", 1: "S", 17: "T", 32: "U", 9: "V", 13: "W", 7: "X",
            16: "Y", 6: "Z",
        ]
        if let letter = letters[keyCode] { return letter }
        let specials: [UInt32: String] = [
            UInt32(kVK_Space): "Space",
            UInt32(kVK_Return): "↩",
            UInt32(kVK_Tab): "Tab",
            UInt32(kVK_Delete): "⌫",
            UInt32(kVK_Escape): "Esc",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
            98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
            105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17", 79: "F18",
            80: "F19", 90: "F20",
        ]
        if let special = specials[keyCode] { return special }
        let symbols: [UInt32: String] = [
            18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6",
            26: "7", 28: "8", 25: "9", 29: "0", 27: "-", 24: "=",
            33: "[", 30: "]", 42: "\\", 41: ";", 39: "'", 43: ",", 47: ".", 44: "/", 50: "`",
        ]
        if let symbol = symbols[keyCode] { return symbol }
        return "Key\(keyCode)"
    }
}

struct HotKeyRegistrationTestSeam {
    let register: (Shortcut) -> Bool
    let unregister: (Shortcut) -> Void
}

/// 多快捷键全局热键管理器（基于 Carbon）。
final class GlobalHotKeyManager {
    private var handler: EventHandlerRef?
    private var refs: [Shortcut: EventHotKeyRef] = [:]
    private var testRefs: Set<Shortcut> = []
    private let testRegistration: HotKeyRegistrationTestSeam?
    private var ids: [UInt32: Shortcut] = [:]
    private var actions: [Shortcut: () -> Void] = [:]
    private var nextID: UInt32 = 1

    init(testRegistration: HotKeyRegistrationTestSeam? = nil) {
        self.testRegistration = testRegistration
    }

    deinit { unregisterAll() }

    /// 注册一个快捷键；成功返回 nil，失败返回错误信息。
    func register(_ shortcut: Shortcut, action: @escaping () -> Void) -> String? {
        guard !isRegistered(shortcut) else { return "快捷键已注册" }
        if let testRegistration {
            guard testRegistration.register(shortcut) else { return "快捷键已被占用" }
            testRefs.insert(shortcut)
            actions[shortcut] = action
            return nil
        }
        if refs.isEmpty {
            guard installHandler() else { return "全局快捷键事件处理器注册失败" }
        }
        let id = nextID
        nextID += 1
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            shortcut.keyCode, shortcut.modifiers,
            EventHotKeyID(signature: OSType(0x44534851), id: id),
            GetApplicationEventTarget(), 0, &ref
        )
        guard status == noErr, let ref else {
            if refs.isEmpty { removeHandler() }
            return "快捷键已被占用（\(status)）"
        }
        refs[shortcut] = ref
        ids[id] = shortcut
        actions[shortcut] = action
        return nil
    }

    /// 替换快捷键；新快捷键注册成功后才释放旧快捷键。
    func replace(_ previous: Shortcut, with shortcut: Shortcut, action: @escaping () -> Void) -> String? {
        if previous == shortcut {
            guard isRegistered(previous) else { return register(shortcut, action: action) }
            actions[previous] = action
            return nil
        }
        if let error = register(shortcut, action: action) { return error }
        unregister(previous)
        return nil
    }

    func unregister(_ shortcut: Shortcut) {
        if testRefs.remove(shortcut) != nil {
            testRegistration?.unregister(shortcut)
            actions.removeValue(forKey: shortcut)
            return
        }
        if let ref = refs.removeValue(forKey: shortcut) {
            UnregisterEventHotKey(ref)
        }
        for (id, s) in ids where s == shortcut { ids.removeValue(forKey: id) }
        actions.removeValue(forKey: shortcut)
        if refs.isEmpty { removeHandler() }
    }

    func unregisterAll() {
        if let testRegistration {
            for shortcut in testRefs { testRegistration.unregister(shortcut) }
            testRefs.removeAll()
            ids.removeAll()
            actions.removeAll()
            return
        }
        for (_, ref) in refs { UnregisterEventHotKey(ref) }
        refs.removeAll()
        ids.removeAll()
        actions.removeAll()
        removeHandler()
    }

    func dispatch(_ shortcut: Shortcut) { actions[shortcut]?() }

    private func isRegistered(_ shortcut: Shortcut) -> Bool {
        refs[shortcut] != nil || testRefs.contains(shortcut)
    }

    private func installHandler() -> Bool {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let pointer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let userData, let event else { return OSStatus(eventNotHandledErr) }
            let owner = Unmanaged<GlobalHotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            var hotKeyID = EventHotKeyID()
            let got = withUnsafeMutablePointer(to: &hotKeyID) { ptr in
                GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                  MemoryLayout<EventHotKeyID>.size, nil, UnsafeMutableRawPointer(ptr))
            }
            guard got == noErr else { return OSStatus(eventNotHandledErr) }
            DispatchQueue.main.async {
                if let shortcut = owner.ids[hotKeyID.id] {
                    owner.dispatch(shortcut)
                }
            }
            return noErr
        }, 1, &eventType, pointer, &handler)
        return status == noErr
    }

    private func removeHandler() {
        if let handler { RemoveEventHandler(handler) }
        handler = nil
    }
}
