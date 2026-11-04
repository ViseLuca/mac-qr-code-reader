import Foundation

/// The user's global shortcuts, persisted in UserDefaults and registered with `HotKeyCenter`.
@MainActor
final class Shortcuts: ObservableObject {
    private static let key = "shortcuts"

    /// Actions without an entry have no shortcut.
    @Published private(set) var assigned: [ShortcutAction: Shortcut] = [:]
    /// Shortcuts macOS refused to register, usually because another app already uses them.
    @Published private(set) var unavailable: Set<ShortcutAction> = []

    /// While a new shortcut is being recorded none is registered: they would fire instead of being recorded.
    var isSuspended = false {
        didSet { if isSuspended != oldValue { register() } }
    }

    private var handlers: [ShortcutAction: @MainActor () -> Void] = [:]

    init() {
        // Saved as action → shortcut, with null for a shortcut the user removed. Missing actions get the default.
        var saved: [String: Shortcut?] = [:]
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode([String: Shortcut?].self, from: data) {
            saved = decoded
        }
        for action in ShortcutAction.allCases {
            switch saved[action.rawValue] {
            case .none: assigned[action] = action.defaultShortcut
            case .some(.none): break
            case .some(.some(let shortcut)): assigned[action] = shortcut
            }
        }
    }

    func start(handlers: [ShortcutAction: @MainActor () -> Void]) {
        self.handlers = handlers
        register()
    }

    /// Assigns `shortcut` (nil removes it), taking it away from any other action that had it.
    func set(_ shortcut: Shortcut?, for action: ShortcutAction) {
        if let shortcut {
            for (other, current) in assigned where other != action && current == shortcut {
                assigned[other] = nil
            }
        }
        assigned[action] = shortcut
        let saved = Dictionary(uniqueKeysWithValues: ShortcutAction.allCases.map { ($0.rawValue, assigned[$0]) })
        UserDefaults.standard.set(try? JSONEncoder().encode(saved), forKey: Self.key)
        register()
    }

    private func register() {
        HotKeyCenter.shared.unregisterAll()
        guard !isSuspended else { return }
        var refused: Set<ShortcutAction> = []
        for action in ShortcutAction.allCases {
            guard let shortcut = assigned[action], let handler = handlers[action] else { continue }
            if !HotKeyCenter.shared.register(keyCode: shortcut.keyCode, modifiers: shortcut.modifiers, handler: handler) {
                refused.insert(action)
            }
        }
        unavailable = refused
    }
}
