import Foundation
import CryptoKit
import AppKit

/// Läuft rekursiv durch den Benutzerordner und liefert alle normalen Dateien.
enum HomeWalker {
    struct File: Sendable {
        let url: URL
        let size: Int64
        let created: Date?
        let inode: UInt64?
    }

    /// - Parameter skipTopLevel: Ordner direkt im Benutzerordner, die ausgelassen werden.
    /// - Parameter skipNames: Ordnernamen, die überall ausgelassen werden.
    /// - Parameter skipExtensions: Pakete (z. B. „photoslibrary“, „app“), die nicht betreten werden.
    static func walk(home: URL, skipTopLevel: Set<String>, skipNames: Set<String>, skipExtensions: Set<String>,
                     extraSkip: [String] = [], visit: (File, String) -> Void) {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .creationDateKey, .fileIdentifierKey]
        for top in FS.children(of: home) {
            let topName = top.lastPathComponent
            if skipTopLevel.contains(topName) { continue }
            if extraSkip.contains(where: { top.path == $0 || top.path.hasPrefix($0 + "/") }) { continue }
            guard let e = FS.fm.enumerator(at: top, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in true }) else { continue }
            // Einzelne Datei direkt im Benutzerordner
            if !FS.isDirectory(top) {
                if let v = try? top.resourceValues(forKeys: Set(keys)), v.isRegularFile == true {
                    visit(File(url: top, size: Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0), created: v.creationDate, inode: nil), topName)
                }
                continue
            }
            for case let url as URL in e {
                guard let v = try? url.resourceValues(forKeys: Set(keys)) else { continue }
                if v.isSymbolicLink == true { continue }
                if v.isDirectory == true {
                    if skipNames.contains(url.lastPathComponent) || skipExtensions.contains(url.pathExtension.lowercased())
                        || extraSkip.contains(where: { url.path == $0 }) {
                        e.skipDescendants()
                    }
                    continue
                }
                guard v.isRegularFile == true else { continue }
                let inode = v.fileIdentifier
                visit(File(url: url, size: Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0), created: v.creationDate, inode: inode), topName)
            }
        }
    }
}

// MARK: - Grosse Dateien + Ordnerübersicht

struct LargeFilesScanner: Scanner {
    let category = CategoryID.largeFiles

    func scan(_ rules: RuleSnapshot) async -> CategoryResult {
        let threshold = Int64(rules.largeFileGB * 1_000_000_000)
        var perTop: [String: Int64] = [:]
        var items: [CleanupItem] = []
        HomeWalker.walk(home: rules.home,
                        skipTopLevel: ["Library", ".Trash"],
                        skipNames: [],
                        skipExtensions: ["photoslibrary"],
                        extraSkip: rules.protectedPaths) { file, top in
            perTop[top, default: 0] += file.size
            if file.size >= threshold {
                items.append(CleanupItem(category: category, url: file.url, title: file.url.lastPathComponent,
                                         detail: FS.pretty(file.url.deletingLastPathComponent()),
                                         size: file.size, method: .trash, preselected: false,
                                         groupKey: top))
            }
        }
        // Übersicht: inkl. Library, Fotos-Mediathek (in Pictures) und Papierkorb – damit man sieht, wo der Platz steckt.
        var overview = perTop.map { FolderUsage(url: rules.home.appending(path: $0.key), size: $0.value) }
        for name in ["Library", ".Trash"] {
            let url = rules.home.appending(path: name)
            overview.append(FolderUsage(url: url, size: FS.allocatedSize(of: url)))
        }
        // Fotos-Mediatheken wurden beim Durchlaufen ausgelassen → separat zählen
        let pictures = rules.home.appending(path: "Pictures")
        for lib in FS.children(of: pictures) where lib.pathExtension == "photoslibrary" {
            overview.append(FolderUsage(url: lib, size: FS.allocatedSize(of: lib)))
        }
        overview.sort { $0.size > $1.size }
        return CategoryResult(category: category, items: items, overview: overview)
    }
}

// MARK: - Doppelte Dateien

struct DuplicatesScanner: Scanner {
    let category = CategoryID.duplicates

    static func hash(_ url: URL, limit: Int? = nil) -> String? {
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        var hasher = SHA256()
        var read = 0
        while true {
            let chunk = (try? h.read(upToCount: 1 << 20)) ?? nil
            guard let chunk, !chunk.isEmpty else { break }
            hasher.update(data: chunk)
            read += chunk.count
            if let limit, read >= limit { break }
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    func scan(_ rules: RuleSnapshot) async -> CategoryResult {
        let minSize = Int64(rules.duplicateMinMB) * 1_000_000
        var bySize: [Int64: [HomeWalker.File]] = [:]
        HomeWalker.walk(home: rules.home,
                        skipTopLevel: ["Library", ".Trash", "Developer", "Applications"],
                        skipNames: [".git", "node_modules", "DerivedData", ".build", "Pods"],
                        skipExtensions: ["photoslibrary", "app", "xcarchive", "xcodeproj", "xcworkspace", "framework", "bundle", "musiclibrary", "tvlibrary", "fcpbundle", "lrlibrary", "lrdata"],
                        extraSkip: rules.protectedPaths) { file, _ in
            if file.size >= minSize { bySize[file.size, default: []].append(file) }
        }
        var items: [CleanupItem] = []
        for (_, files) in bySize where files.count > 1 {
            // Hardlinks (gleiche Datei-ID) zählen nicht als Duplikat.
            var seen = Set<UInt64>()
            let unique = files.filter { f in f.inode.map { seen.insert($0).inserted } ?? true }
            guard unique.count > 1 else { continue }
            // Erst die ersten 64 KB vergleichen, dann nur bei Treffern die ganze Datei.
            let byPartial = Dictionary(grouping: unique) { Self.hash($0.url, limit: 65_536) ?? UUID().uuidString }
            for (_, candidates) in byPartial where candidates.count > 1 {
                let byFull = Dictionary(grouping: candidates) { Self.hash($0.url) ?? UUID().uuidString }
                for (digest, group) in byFull where group.count > 1 {
                    let sorted = group.sorted { ($0.created ?? .distantFuture) < ($1.created ?? .distantFuture) }
                    let original = sorted[0]
                    for (i, f) in sorted.enumerated() {
                        let keep = i == 0
                        items.append(CleanupItem(
                            category: category, url: f.url, title: f.url.lastPathComponent,
                            detail: keep ? "Älteste Kopie – bleibt · \(FS.pretty(f.url.deletingLastPathComponent()))"
                                         : "\(FS.pretty(f.url.deletingLastPathComponent())) · Original: \(FS.pretty(original.url))",
                            size: f.size, method: .trash, preselected: !keep,
                            groupKey: "\(original.url.lastPathComponent) · \(String(digest.prefix(8)))"))
                    }
                }
            }
        }
        return CategoryResult(category: category, items: items,
                              notice: "Hinweis: Auf APFS können Kopien Speicher teilen (Klone). Dann gibt das Löschen weniger frei als angezeigt.")
    }
}

// MARK: - Reste deinstallierter Apps

struct AppLeftoversScanner: Scanner {
    let category = CategoryID.appLeftovers

    static let bundleIDPattern = #"^[A-Za-z0-9-]+(\.[A-Za-z0-9_-]+){2,}$"#

    /// Macht aus Ordner-/Dateinamen eine Bundle-ID (oder nil, wenn es keine ist).
    static func bundleID(from name: String) -> String? {
        var n = name
        for ext in [".plist", ".savedState", ".binarycookies"] where n.hasSuffix(ext) { n = String(n.dropLast(ext.count)) }
        if n.hasPrefix("group.") { n = String(n.dropFirst(6)) }
        // Group Containers: „TEAMID12AB.com.firma.app“
        if let r = n.range(of: #"^[A-Z0-9]{10}\."#, options: .regularExpression) { n = String(n[r.upperBound...]) }
        guard n.range(of: bundleIDPattern, options: .regularExpression) != nil else { return nil }
        let lower = n.lowercased()
        let applePrefixes = ["com.apple.", "apple.", "systemgroup.", "com.apple"]
        if applePrefixes.contains(where: { lower.hasPrefix($0) }) { return nil }
        return n
    }

    /// Gilt als installiert, wenn eine installierte App gleich heisst oder die IDs ineinander passen
    /// (z. B. „com.firma.app.helper“ gehört zu „com.firma.app“).
    static func isInstalled(_ id: String, installed: Set<String>) -> Bool {
        let l = id.lowercased()
        return installed.contains { inst in
            l == inst || l.hasPrefix(inst + ".") || inst.hasPrefix(l + ".")
        }
    }

    static func installedBundleIDs() -> Set<String> {
        var ids = Set<String>()
        let roots = ["/Applications", "/System/Applications", "/System/Library/CoreServices",
                     FS.fm.homeDirectoryForCurrentUser.appending(path: "Applications").path]
        for root in roots {
            guard let e = FS.fm.enumerator(at: URL(fileURLWithPath: root), includingPropertiesForKeys: [.isDirectoryKey],
                                           options: [.skipsHiddenFiles], errorHandler: { _, _ in true }) else { continue }
            for case let url as URL in e {
                if e.level > 6 { e.skipDescendants(); continue }
                guard url.pathExtension == "app" || url.pathExtension == "appex" else { continue }
                if let id = Bundle(url: url)?.bundleIdentifier { ids.insert(id.lowercased()) }
                // Hilfs-Apps in Contents/ dürfen weiter durchsucht werden, Rest nicht
                if url.pathExtension == "appex" { e.skipDescendants() }
            }
        }
        return ids
    }

    func scan(_ rules: RuleSnapshot) async -> CategoryResult {
        let installed = Self.installedBundleIDs()
        let vendors = Set(installed.map { $0.split(separator: ".").prefix(2).joined(separator: ".") })
        let places = ["Library/Application Support", "Library/Containers", "Library/Group Containers",
                      "Library/Preferences", "Library/Saved Application State", "Library/HTTPStorages",
                      "Library/WebKit", "Library/Cookies"]
        var items: [CleanupItem] = []
        for place in places {
            let dir = rules.home.appending(path: place)
            for url in FS.children(of: dir) {
                guard let id = Self.bundleID(from: url.lastPathComponent) else { continue }
                guard !Self.isInstalled(id, installed: installed) else { continue }
                // Läuft die App gerade (z. B. aus einem anderen Ordner gestartet)? Dann überspringen.
                guard !rules.runningBundleIDs.contains(where: { $0.lowercased() == id.lowercased() }) else { continue }
                // Doppelte Absicherung über LaunchServices.
                if NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) != nil { continue }
                let size = FS.allocatedSize(of: url)
                let vendor = id.lowercased().split(separator: ".").prefix(2).joined(separator: ".")
                items.append(CleanupItem(
                    category: category, url: url, title: id,
                    detail: FS.pretty(url),
                    size: size, method: .trash, preselected: false,
                    warning: vendors.contains(vendor) ? "Vom gleichen Hersteller ist noch eine App installiert" : nil,
                    groupKey: id))
            }
        }
        return CategoryResult(category: category, items: items)
    }
}

// MARK: - iPhone-Backups (nur Ansicht)

struct IOSBackupsScanner: Scanner {
    let category = CategoryID.iosBackups

    func scan(_ rules: RuleSnapshot) async -> CategoryResult {
        let root = rules.home.appending(path: "Library/Application Support/MobileSync/Backup")
        let items = FS.children(of: root).filter(FS.isDirectory).map { dir -> CleanupItem in
            let info = FS.plist(at: dir.appending(path: "Info.plist")) ?? [:]
            let name = info["Device Name"] as? String ?? dir.lastPathComponent
            let date = info["Last Backup Date"] as? Date
            return CleanupItem(category: category, url: dir, title: name,
                               detail: date.map { "Letztes Backup: \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "",
                               size: FS.allocatedSize(of: dir), method: .infoOnly, preselected: false)
        }
        return CategoryResult(category: category, items: items,
                              notice: items.isEmpty ? "Keine lokalen Backups gefunden." : nil)
    }
}

// MARK: - Lokale Snapshots (nur Ansicht)

struct LocalSnapshotsScanner: Scanner {
    let category = CategoryID.localSnapshots

    func scan(_ rules: RuleSnapshot) async -> CategoryResult {
        let out = await Shell.run("/usr/bin/tmutil", ["listlocalsnapshots", "/"])
        let names = out.stdout.split(separator: "\n").map(String.init).filter { $0.hasPrefix("com.apple") }
        let items = names.map {
            CleanupItem(category: category, url: nil, title: $0, detail: "Grösse wird von macOS nicht angegeben",
                        size: 0, method: .infoOnly, preselected: false, id: "snap:\($0)")
        }
        return CategoryResult(category: category, items: items,
                              notice: items.isEmpty ? "Keine lokalen Snapshots vorhanden." : nil)
    }
}
