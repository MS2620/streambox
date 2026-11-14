import Foundation

/// A programme the user asked to be reminded about.
struct ProgrammeReminder: Codable, Identifiable, Hashable {
    let channelID: Int
    let channelName: String
    let channelIcon: String?
    let channelNumber: Int?
    let title: String
    let start: Date
    let end: Date

    var id: String { "\(channelID)|\(Int(start.timeIntervalSince1970))" }

    var channel: XtreamChannel {
        XtreamChannel(id: channelID, number: channelNumber, name: channelName, icon: channelIcon)
    }

    /// "Today 15:00", "Sun 20:00".
    var whenLabel: String {
        "\(DayFormat.label(start)) \(DayFormat.time(start))"
    }
}

/// Reminders, kept on the Apple TV. While StreamBox is open it watches the clock and
/// raises `due` when a programme starts; tvOS has no notifications, so a closed app misses them.
@MainActor
final class ReminderStore: ObservableObject {
    static let shared = ReminderStore()

    @Published private(set) var reminders: [ProgrammeReminder] = []
    /// The reminder to show now, if any.
    @Published private(set) var due: ProgrammeReminder?

    private static let storageKey = "programmeReminders"
    /// Shown this long before the start, so there's time to switch.
    private static let lead: TimeInterval = 30

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode([ProgrammeReminder].self, from: data) {
            reminders = saved.filter { $0.end > Date() }.sorted { $0.start < $1.start }
        }
    }

    func isSet(channelID: Int, start: Date) -> Bool {
        reminders.contains { $0.channelID == channelID && $0.start == start }
    }

    func add(_ reminder: ProgrammeReminder) {
        guard !reminders.contains(where: { $0.id == reminder.id }) else { return }
        reminders.append(reminder)
        reminders.sort { $0.start < $1.start }
        save()
    }

    func remove(_ reminder: ProgrammeReminder) {
        reminders.removeAll { $0.id == reminder.id }
        save()
    }

    /// Replaces the reminders with a backup's (past ones are dropped).
    func restore(_ saved: [ProgrammeReminder]) {
        reminders = saved.filter { $0.end > Date() }.sorted { $0.start < $1.start }
        save()
    }

    func dismissDue() {
        due = nil
    }

    /// Checks the clock every 10 seconds. Started once from the app's root view.
    func run() async {
        while !Task.isCancelled {
            check()
            try? await Task.sleep(for: .seconds(10))
        }
    }

    private func check() {
        let now = Date()
        // Programmes that have ended are dropped, reminded or not.
        let before = reminders.count
        reminders.removeAll { $0.end <= now }
        // One at a time: the next waits until the shown one is dismissed or acted on.
        if due == nil, let next = reminders.first(where: { $0.start <= now.addingTimeInterval(Self.lead) }) {
            due = next
            reminders.removeAll { $0.id == next.id }
        }
        if reminders.count != before || due != nil { save() }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(reminders) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}
