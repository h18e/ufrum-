import Foundation
import AppKit
import Observation
import ServiceManagement
import UserNotifications

/// Einstellungen – werden in den UserDefaults gespeichert.
@Observable
@MainActor
final class Preferences {
    private let d = UserDefaults.standard

    var dryRun: Bool { didSet { d.set(dryRun, forKey: "dryRun") } }
    var derivedDataDays: Int { didSet { d.set(derivedDataDays, forKey: "derivedDataDays") } }
    var simulatorDays: Int { didSet { d.set(simulatorDays, forKey: "simulatorDays") } }
    var archivesToKeep: Int { didSet { d.set(archivesToKeep, forKey: "archivesToKeep") } }
    var downloadsDays: Int { didSet { d.set(downloadsDays, forKey: "downloadsDays") } }
    var largeFileGB: Double { didSet { d.set(largeFileGB, forKey: "largeFileGB") } }
    var duplicateMinMB: Int { didSet { d.set(duplicateMinMB, forKey: "duplicateMinMB") } }
    var lowSpaceWarningGB: Int { didSet { d.set(lowSpaceWarningGB, forKey: "lowSpaceWarningGB") } }
    var protectedPaths: [String] { didSet { d.set(protectedPaths, forKey: "protectedPaths") } }
    var ignoredIDs: [String] { didSet { d.set(ignoredIDs, forKey: "ignoredIDs") } }
    /// Bereiche, die beim Scan ausgelassen werden.
    var disabledCategories: [String] { didSet { d.set(disabledCategories, forKey: "disabledCategories") } }

    init() {
        d.register(defaults: [
            "dryRun": true, // Probelauf ist standardmässig an
            "derivedDataDays": 14, "simulatorDays": 60, "archivesToKeep": 3, "downloadsDays": 90,
            "largeFileGB": 1.0, "duplicateMinMB": 1, "lowSpaceWarningGB": 20,
        ])
        dryRun = d.bool(forKey: "dryRun")
        derivedDataDays = d.integer(forKey: "derivedDataDays")
        simulatorDays = d.integer(forKey: "simulatorDays")
        archivesToKeep = d.integer(forKey: "archivesToKeep")
        downloadsDays = d.integer(forKey: "downloadsDays")
        largeFileGB = d.double(forKey: "largeFileGB")
        duplicateMinMB = d.integer(forKey: "duplicateMinMB")
        lowSpaceWarningGB = d.integer(forKey: "lowSpaceWarningGB")
        protectedPaths = d.stringArray(forKey: "protectedPaths") ?? []
        ignoredIDs = d.stringArray(forKey: "ignoredIDs") ?? []
        disabledCategories = d.stringArray(forKey: "disabledCategories") ?? []
    }

    func isEnabled(_ c: CategoryID) -> Bool { !disabledCategories.contains(c.rawValue) }
    func setEnabled(_ c: CategoryID, _ on: Bool) {
        disabledCategories.removeAll { $0 == c.rawValue }
        if !on { disabledCategories.append(c.rawValue) }
    }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("Ufrumä: Anmeldeobjekt konnte nicht geändert werden: \(error)")
            }
        }
    }
}

/// Zentraler Zustand der App: Scan-Ergebnisse, Auswahl, Aufräumen, Verlauf.
@Observable
@MainActor
final class AppModel {
    let prefs = Preferences()

    var results: [CategoryID: CategoryResult] = [:]
    var selection: Set<String> = []
    var scanning: Set<CategoryID> = []
    var lastScan: Date?
    var cleaning = false
    var cleanProgress: (done: Int, total: Int) = (0, 0)
    var lastOutcome: Cleaner.Outcome?
    var lastOutcomeWasDryRun = false
    var history: [HistoryEntry] = HistoryStore.load()
    var freeSpace: Int64 = 0
    var totalSpace: Int64 = 0
    var hasFullDiskAccess = FS.hasFullDiskAccess()

    private var lowSpaceNotified = false
    private var timer: Timer?

    init() {
        refreshDiskInfo()
        timer = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshDiskInfo() }
        }
    }

    var isScanning: Bool { !scanning.isEmpty }

    // MARK: Freier Speicher + Warnung

    var isLowOnSpace: Bool { freeSpace > 0 && freeSpace < Int64(prefs.lowSpaceWarningGB) * 1_000_000_000 }

    func refreshDiskInfo() {
        let info = FS.freeSpace()
        freeSpace = info.free
        totalSpace = info.total
        hasFullDiskAccess = FS.hasFullDiskAccess()
        if isLowOnSpace && !lowSpaceNotified {
            lowSpaceNotified = true
            notifyLowSpace()
        } else if !isLowOnSpace {
            lowSpaceNotified = false
        }
    }

    private func notifyLowSpace() {
        let center = UNUserNotificationCenter.current()
        let free = freeSpace.bytes
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "Wenig Speicher frei"
            content.body = "Nur noch \(free) frei. Öffne Ufrumä, um aufzuräumen."
            center.add(UNNotificationRequest(identifier: "lowspace", content: content, trigger: nil))
        }
    }

    // MARK: Scan

    func rules() -> RuleSnapshot {
        let running = NSWorkspace.shared.runningApplications
        return RuleSnapshot(
            derivedDataDays: prefs.derivedDataDays,
            simulatorDays: prefs.simulatorDays,
            archivesToKeep: prefs.archivesToKeep,
            downloadsDays: prefs.downloadsDays,
            largeFileGB: prefs.largeFileGB,
            duplicateMinMB: prefs.duplicateMinMB,
            protectedPaths: prefs.protectedPaths,
            ignoredIDs: Set(prefs.ignoredIDs),
            home: FS.fm.homeDirectoryForCurrentUser,
            runningBundleIDs: Set(running.compactMap(\.bundleIdentifier)),
            runningAppNames: Set(running.compactMap(\.localizedName)))
    }

    /// - Parameter quick: lässt die aufwändigen Bereiche (Grosse Dateien, Duplikate) aus.
    func scan(_ categories: [CategoryID]? = nil, quick: Bool = false) {
        guard !isScanning, !cleaning else { return }
        var list = categories ?? CategoryID.allCases.filter { prefs.isEnabled($0) }
        if quick { list.removeAll(where: \.isSlow) }
        for c in list {
            selection.subtract(results[c]?.items.map(\.id) ?? [])
            results[c] = nil
        }
        scanning = Set(list)
        lastOutcome = nil
        let rules = rules()
        Task {
            await ScanEngine.run(list, rules: rules) { result in
                await MainActor.run {
                    self.results[result.category] = result
                    self.selection.formUnion(result.items.filter { $0.preselected && $0.method != .infoOnly }.map(\.id))
                    self.scanning.remove(result.category)
                }
            }
            self.lastScan = Date()
            self.refreshDiskInfo()
        }
    }

    // MARK: Auswahl

    func items(in c: CategoryID) -> [CleanupItem] { results[c]?.items ?? [] }

    func selectedItems(in c: CategoryID? = nil) -> [CleanupItem] {
        let cats = c.map { [$0] } ?? CategoryID.allCases
        return cats.flatMap { items(in: $0) }.filter { selection.contains($0.id) && $0.method != .infoOnly }
    }

    func selectedSize(in c: CategoryID? = nil) -> Int64 { selectedItems(in: c).reduce(0) { $0 + $1.size } }

    func toggle(_ item: CleanupItem) {
        guard item.method != .infoOnly else { return }
        if selection.contains(item.id) { selection.remove(item.id) } else { selection.insert(item.id) }
    }

    func setAll(_ on: Bool, in c: CategoryID) {
        let ids = items(in: c).filter { $0.method != .infoOnly }.map(\.id)
        if on { selection.formUnion(ids) } else { selection.subtract(ids) }
    }

    /// „Immer ignorieren“: Eintrag kommt nie wieder in einen Vorschlag.
    func ignore(_ item: CleanupItem) {
        prefs.ignoredIDs.append(item.id)
        selection.remove(item.id)
        results[item.category]?.items.removeAll { $0.id == item.id }
    }

    func protect(_ url: URL) {
        let path = url.standardizedFileURL.path
        guard !prefs.protectedPaths.contains(path) else { return }
        prefs.protectedPaths.append(path)
        for c in CategoryID.allCases {
            let removed = results[c]?.items.filter { $0.url.map { $0.path == path || $0.path.hasPrefix(path + "/") } ?? false } ?? []
            selection.subtract(removed.map(\.id))
            results[c]?.items.removeAll { removed.contains($0) }
        }
    }

    // MARK: Aufräumen

    func clean() {
        guard !cleaning else { return }
        let items = selectedItems()
        guard !items.isEmpty else { return }
        cleaning = true
        cleanProgress = (0, items.count)
        let dryRun = prefs.dryRun
        let cleaner = Cleaner(dryRun: dryRun, home: FS.fm.homeDirectoryForCurrentUser, protectedPaths: prefs.protectedPaths)
        Task {
            let outcome = await cleaner.clean(items) { done, total in
                Task { @MainActor in self.cleanProgress = (done, total) }
            }
            self.lastOutcome = outcome
            self.lastOutcomeWasDryRun = dryRun
            self.cleaning = false
            let entry = HistoryEntry(date: Date(), dryRun: dryRun,
                                     perCategory: Dictionary(uniqueKeysWithValues: outcome.freed.map { ($0.key.rawValue, $0.value) }),
                                     itemCount: outcome.processed, failures: outcome.failures)
            self.history.insert(entry, at: 0)
            HistoryStore.save(self.history)
            if !dryRun {
                // Erledigte Einträge aus der Liste nehmen
                let done = Set(items.map(\.id)).subtracting(outcome.failedIDs)
                for c in CategoryID.allCases {
                    self.results[c]?.items.removeAll { done.contains($0.id) }
                }
                self.selection.subtract(done)
            }
            self.refreshDiskInfo()
        }
    }

    var totalFreedEver: Int64 { history.filter { !$0.dryRun }.reduce(0) { $0 + $1.total } }

    func clearHistory() {
        history.removeAll()
        HistoryStore.save(history)
    }

    // MARK: Systemeinstellungen

    func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
}
