import Foundation

/// Most recent scans, persisted in UserDefaults.
@MainActor
final class History: ObservableObject {
    struct Item: Codable, Identifiable, Hashable {
        var id = UUID()
        var raw: String
        var date = Date()
    }

    private static let key = "history"
    private static let limit = 20

    @Published private(set) var items: [Item] = []

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode([Item].self, from: data) {
            items = saved
        }
    }

    func add(_ raw: String) {
        items.removeAll { $0.raw == raw }
        items.insert(Item(raw: raw), at: 0)
        items = Array(items.prefix(Self.limit))
        save()
    }

    func clear() {
        items = []
        save()
    }

    private func save() {
        UserDefaults.standard.set(try? JSONEncoder().encode(items), forKey: Self.key)
    }
}
