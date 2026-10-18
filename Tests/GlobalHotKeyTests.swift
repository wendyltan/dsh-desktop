import Carbon.HIToolbox
import Foundation

@main
struct GlobalHotKeyTests {
    static func main() {
        var failures = 0
        func expect(_ condition: Bool, _ label: String) {
            if condition { print("PASS  \(label)") }
            else { failures += 1; print("FAIL  \(label)") }
        }

        let registry = TestHotKeyRegistry()
        func makeManager() -> GlobalHotKeyManager {
            GlobalHotKeyManager(testRegistration: HotKeyRegistrationTestSeam(
                register: { registry.register($0) },
                unregister: { registry.unregister($0) }
            ))
        }
        let owner = makeManager()
        let competitor = makeManager()
        let blocker = makeManager()
        let observer = makeManager()
        defer { owner.unregisterAll(); competitor.unregisterAll(); blocker.unregisterAll(); observer.unregisterAll() }

        let first = Shortcut(keyCode: 113, modifiers: UInt32(controlKey | optionKey | shiftKey | cmdKey))
        let second = Shortcut(keyCode: 107, modifiers: UInt32(controlKey | optionKey | shiftKey | cmdKey))
        var action = 0

        expect(owner.replace(first, with: first, action: { action = 1 }) == nil,
               "replacement registers when the saved shortcut was not active")
        expect(owner.register(first, action: { action = 2 }) != nil, "duplicate registration is rejected")
        owner.dispatch(first)
        expect(action == 1, "duplicate registration preserves the original action")
        expect(competitor.register(first, action: {}) != nil, "duplicate does not release the original shortcut")

        expect(blocker.register(second, action: {}) == nil, "register isolated replacement target")
        expect(owner.replace(first, with: second, action: { action = 3 }) != nil,
               "occupied replacement target is rejected")
        expect(observer.register(first, action: {}) != nil, "failed replacement preserves the old shortcut")
        owner.dispatch(first)
        expect(action == 1, "failed replacement preserves the old action")
        blocker.unregisterAll()
        observer.unregisterAll()

        expect(owner.replace(first, with: second, action: { action = 4 }) == nil, "available replacement succeeds")
        expect(observer.register(first, action: {}) == nil, "successful replacement releases the old shortcut")
        expect(blocker.register(second, action: {}) != nil, "successful replacement owns the new shortcut")
        owner.dispatch(second)
        expect(action == 4, "successful replacement installs the new action")
        observer.unregisterAll()
        blocker.unregisterAll()

        expect(owner.replace(second, with: second, action: { action = 5 }) == nil, "same-key replacement succeeds")
        owner.dispatch(second)
        expect(action == 5, "same-key replacement updates the action")
        expect(competitor.register(second, action: {}) != nil, "same-key replacement retains its registration")

        expect(Shortcut.keyLabel(122) == "F1", "F1 label uses its Carbon key code")
        expect(Shortcut.keyLabel(120) == "F2", "F2 label uses its Carbon key code")
        expect(Shortcut.keyLabel(113) == "F15", "F15 label uses its Carbon key code")

        if let resultPath = CommandLine.arguments.dropFirst().first {
            let result: [String: Any] = ["passed": failures == 0, "failures": failures]
            do {
                try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]).write(to: URL(fileURLWithPath: resultPath), options: .atomic)
            } catch {
                fputs("could not write result file: \(error)\n", stderr)
                exit(2)
            }
        }
        if failures > 0 { exit(1) }
        print("all assertions passed")
    }
}

private final class TestHotKeyRegistry {
    private var shortcuts: Set<Shortcut> = []

    func register(_ shortcut: Shortcut) -> Bool { shortcuts.insert(shortcut).inserted }
    func unregister(_ shortcut: Shortcut) { shortcuts.remove(shortcut) }
}
