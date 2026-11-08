import Foundation

/// Cache-Ordner, die schon von einem anderen Bereich erfasst werden.
let cachesHandledElsewhere: Set<String> = [
    "com.apple.dt.Xcode", "org.swift.swiftpm", "pip", "Yarn", "CocoaPods", "Homebrew",
]

// MARK: - App-Caches

struct AppCachesScanner: Scanner {
    let category = CategoryID.caches

    /// Ordnet einen Cache-Ordner einer laufenden App zu (per Bundle-ID oder Name).
    static func runningApp(for folder: String, rules: RuleSnapshot) -> Bool {
        let lower = folder.lowercased()
        if rules.runningBundleIDs.contains(where: { $0.lowercased() == lower }) { return true }
        return rules.runningAppNames.contains { name in
            let n = name.lowercased()
            return n.count > 3 && (lower == n || lower.hasPrefix(n + " ") || lower.contains("." + n))
        }
    }

    func scan(_ rules: RuleSnapshot) async -> CategoryResult {
        let root = rules.home.appending(path: "Library/Caches")
        var items: [CleanupItem] = []
        for folder in FS.children(of: root) {
            let name = folder.lastPathComponent
            guard !cachesHandledElsewhere.contains(name), name != ".DS_Store" else { continue }
            let size = FS.allocatedSize(of: folder)
            guard size >= 1_000_000 else { continue } // Kleinkram unter 1 MB weglassen
            let isApple = name.hasPrefix("com.apple.") || name.hasPrefix("CloudKit") || name == "SiriTTS" || name == "GeoServices"
            let running = Self.runningApp(for: name, rules: rules)
            items.append(CleanupItem(
                category: category, url: folder, title: name,
                detail: isApple ? "Apple-System-Cache – nur bei Bedarf" : FS.pretty(folder),
                size: size, method: .direct,
                preselected: !isApple && !running,
                warning: running ? "App läuft – bitte zuerst beenden" : nil))
        }
        return CategoryResult(category: category, items: items)
    }
}

// MARK: - Logs

struct LogsScanner: Scanner {
    let category = CategoryID.logs

    func scan(_ rules: RuleSnapshot) async -> CategoryResult {
        let root = rules.home.appending(path: "Library/Logs")
        var items: [CleanupItem] = []
        for entry in FS.children(of: root) {
            let name = entry.lastPathComponent
            guard name != "CoreSimulator", name != ".DS_Store" else { continue } // CoreSimulator → Xcode-Caches
            let size = FS.allocatedSize(of: entry)
            guard size > 0 else { continue }
            items.append(CleanupItem(category: category, url: entry, title: name, detail: FS.pretty(entry),
                                     size: size, method: .direct, preselected: true))
        }
        return CategoryResult(category: category, items: items)
    }
}

// MARK: - Entwickler-Caches

struct DevToolCachesScanner: Scanner {
    let category = CategoryID.devToolCaches

    func scan(_ rules: RuleSnapshot) async -> CategoryResult {
        var items: [CleanupItem] = []
        func add(_ rel: String, _ title: String, command: (String, [String])? = nil) {
            let url = rules.home.appending(path: rel)
            guard FS.exists(url) else { return }
            let size = FS.allocatedSize(of: url)
            guard size > 0 else { return }
            let method: DeletionMethod = command.map { .command(executable: $0.0, arguments: $0.1) } ?? .direct
            let how = command.map { "Befehl: \(URL(fileURLWithPath: $0.0).lastPathComponent) \($0.1.joined(separator: " "))" } ?? "Ordner wird gelöscht"
            items.append(CleanupItem(category: category, url: url, title: title, detail: "\(FS.pretty(url)) · \(how)",
                                     size: size, method: method, preselected: true))
        }
        add(".npm/_cacache", "npm", command: Shell.which("npm").map { ($0, ["cache", "clean", "--force"]) })
        add("Library/Caches/pip", "pip", command: (Shell.which("pip3") ?? Shell.which("pip")).flatMap { path in
            // /usr/bin/pip3 ist nur ein Platzhalter, der die Command Line Tools nachinstallieren will → direkt löschen
            path == "/usr/bin/pip3" ? nil : (path, ["cache", "purge"])
        })
        add("Library/Caches/Yarn", "Yarn", command: Shell.which("yarn").map { ($0, ["cache", "clean"]) })
        add("Library/Caches/CocoaPods", "CocoaPods", command: Shell.which("pod").map { ($0, ["cache", "clean", "--all"]) })
        add("Library/Caches/Homebrew", "Homebrew", command: Shell.which("brew").map { ($0, ["cleanup", "--prune=all"]) })
        add(".gradle/caches", "Gradle")
        add(".cache/pnpm", "pnpm")
        add("Library/Caches/pnpm", "pnpm")
        return CategoryResult(category: category, items: items)
    }
}

// MARK: - Papierkorb

struct TrashScanner: Scanner {
    let category = CategoryID.trash

    func scan(_ rules: RuleSnapshot) async -> CategoryResult {
        let root = rules.home.appending(path: ".Trash")
        let children: [URL]
        do { children = try FS.childrenThrowing(of: root) } catch {
            return CategoryResult(category: category, items: [],
                                  notice: "Ohne Festplattenvollzugriff kann Ufrumä den Papierkorb nicht lesen. Siehe Einstellungen → Berechtigung.")
        }
        let items = children.filter { $0.lastPathComponent != ".DS_Store" }.map { url in
            CleanupItem(category: category, url: url, title: url.lastPathComponent,
                        detail: FS.modificationDate(url).map { "Gelöscht ca. \($0.formatted(date: .abbreviated, time: .omitted))" } ?? "",
                        size: FS.allocatedSize(of: url), method: .direct, preselected: true)
        }
        return CategoryResult(category: category, items: items)
    }
}

// MARK: - Downloads

struct DownloadsScanner: Scanner {
    let category = CategoryID.downloads

    func scan(_ rules: RuleSnapshot) async -> CategoryResult {
        let root = rules.home.appending(path: "Downloads")
        let cutoff = Date().addingTimeInterval(-Double(rules.downloadsDays) * 86400)
        let children: [URL]
        do { children = try FS.childrenThrowing(of: root) } catch {
            return CategoryResult(category: category, items: [], notice: "Kein Zugriff auf „Downloads“. Erlaube den Zugriff in der Systemabfrage oder erteile Festplattenvollzugriff.")
        }
        var items: [CleanupItem] = []
        for url in children where !url.lastPathComponent.hasPrefix(".") {
            guard let used = FS.lastUsedDate(url), used < cutoff else { continue }
            items.append(CleanupItem(category: category, url: url, title: url.lastPathComponent,
                                     detail: "Zuletzt verwendet: \(used.formatted(date: .abbreviated, time: .omitted))",
                                     size: FS.allocatedSize(of: url), method: .trash, preselected: true))
        }
        return CategoryResult(category: category, items: items)
    }
}
