import Foundation

/// Ein Scanner sucht in genau einem Bereich nach Löschbarem. Er löscht nie selbst.
protocol Scanner: Sendable {
    var category: CategoryID { get }
    func scan(_ rules: RuleSnapshot) async -> CategoryResult
}

enum ScanEngine {
    static func scanner(for category: CategoryID) -> any Scanner {
        switch category {
        case .deviceSupport: return DeviceSupportScanner()
        case .simulatorDevices: return SimulatorDevicesScanner()
        case .simulatorRuntimes: return SimulatorRuntimesScanner()
        case .derivedData: return DerivedDataScanner()
        case .archives: return ArchivesScanner()
        case .xcodeCaches: return XcodeCachesScanner()
        case .caches: return AppCachesScanner()
        case .logs: return LogsScanner()
        case .devToolCaches: return DevToolCachesScanner()
        case .trash: return TrashScanner()
        case .downloads: return DownloadsScanner()
        case .largeFiles: return LargeFilesScanner()
        case .duplicates: return DuplicatesScanner()
        case .appLeftovers: return AppLeftoversScanner()
        case .iosBackups: return IOSBackupsScanner()
        case .localSnapshots: return LocalSnapshotsScanner()
        }
    }

    /// Scannt die gewünschten Bereiche parallel und meldet jedes fertige Ergebnis sofort.
    static func run(_ categories: [CategoryID],
                    rules: RuleSnapshot,
                    onResult: @escaping @Sendable (CategoryResult) async -> Void) async {
        await withTaskGroup(of: CategoryResult.self) { group in
            for c in categories {
                group.addTask(priority: .utility) {
                    let start = Date()
                    var result = await scanner(for: c).scan(rules)
                    result.items = applyUserFilters(result.items, rules: rules)
                    result.items.sort { $0.size > $1.size }
                    result.duration = Date().timeIntervalSince(start)
                    return result
                }
            }
            for await result in group {
                await onResult(result)
            }
        }
    }

    /// Entfernt Einträge auf der Schutzliste und „Immer ignorieren“-Einträge.
    static func applyUserFilters(_ items: [CleanupItem], rules: RuleSnapshot) -> [CleanupItem] {
        items.filter { item in
            if rules.ignoredIDs.contains(item.id) { return false }
            if let url = item.url, case .denied(let reason) = SafetyGuard.check(url, home: rules.home, protectedPaths: rules.protectedPaths),
               reason == "Steht auf deiner Schutzliste" {
                return false
            }
            return true
        }
    }
}
