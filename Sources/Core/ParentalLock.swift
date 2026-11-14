import Foundation

/// The parental PIN and how long it stays unlocked. The PIN lives in the Keychain;
/// what is locked lives in Preferences.
@MainActor
final class ParentalLock: ObservableObject {
    static let shared = ParentalLock()

    /// Locked things open freely until this time.
    @Published private(set) var unlockedUntil: Date?
    @Published private(set) var hasPIN: Bool

    private static let pinKey = "parentalPIN"

    private init() {
        hasPIN = !(Keychain.string(for: Self.pinKey) ?? "").isEmpty
    }

    var isUnlocked: Bool { (unlockedUntil ?? .distantPast) > Date() }

    func matches(_ entered: String) -> Bool {
        guard let pin = Keychain.string(for: Self.pinKey), !pin.isEmpty else { return true }
        return entered == pin
    }

    func setPIN(_ pin: String?) {
        Keychain.set(pin ?? "", for: Self.pinKey)
        hasPIN = !(pin ?? "").isEmpty
    }

    /// For a backup: the PIN itself.
    var storedPIN: String? {
        let pin = Keychain.string(for: Self.pinKey) ?? ""
        return pin.isEmpty ? nil : pin
    }

    func unlock(minutes: Int) {
        unlockedUntil = Date().addingTimeInterval(TimeInterval(max(minutes, 1)) * 60)
    }

    func lockNow() {
        unlockedUntil = nil
    }

    /// Whether `prefs` lock this Live TV group right now.
    func isLocked(categoryID: String, prefs: Preferences) -> Bool {
        prefs.parentalControlsOn && hasPIN && !isUnlocked && prefs.lockedCategoryIDs.contains(categoryID)
    }

    /// Whether streams from this addon are held back right now.
    func isLocked(addon: AddonEntry, prefs: Preferences) -> Bool {
        prefs.parentalControlsOn && hasPIN && !isUnlocked && prefs.lockedAddonIDs.contains(addon.id)
    }

    /// The settings page itself needs the PIN while controls are on.
    func settingsNeedPIN(prefs: Preferences) -> Bool {
        prefs.parentalControlsOn && hasPIN && !isUnlocked
    }
}
