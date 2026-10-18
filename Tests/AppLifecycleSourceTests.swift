import Foundation

@main
struct AppLifecycleSourceTests {
    static func main() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let app = try String(contentsOf: root.appendingPathComponent("Sources/App.swift"), encoding: .utf8)
        let store = try String(contentsOf: root.appendingPathComponent("Sources/AppStore.swift"), encoding: .utf8)
        var failures = 0

        func expect(_ condition: Bool, _ label: String) {
            if condition { print("PASS  \(label)") }
            else { failures += 1; print("FAIL  \(label)") }
        }

        expect(app.contains("Window(") && app.contains("id: \"client\""),
               "client scene has a stable identity so a closed window can be recreated")
        expect(app.contains("openWindow(id: \"client\")"),
               "client scene registers the SwiftUI reopen action")
        expect(store.contains("if force { showClientPanel() }"),
               "manual update checks restore the alert host before checking")
        expect(!store.contains("NSMenuItem(title: \"桌面端设置…\""),
               "status menu does not duplicate the control center settings entry")

        if failures > 0 { exit(1) }
        print("all assertions passed")
    }
}
