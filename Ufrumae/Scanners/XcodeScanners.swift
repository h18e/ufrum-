import Foundation

private extension RuleSnapshot {
    var developer: URL { home.appending(path: "Library/Developer") }
    var xcode: URL { developer.appending(path: "Xcode") }
}

/// Vergleicht Versionsnummern wie „26.6.1“ numerisch.
enum Version {
    static func parts(_ s: String) -> [Int] { s.split(separator: ".").map { Int($0) ?? 0 } }
    static func isLess(_ a: String, _ b: String) -> Bool {
        let pa = parts(a), pb = parts(b)
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0, y = i < pb.count ? pb[i] : 0
            if x != y { return x < y }
        }
        return false
    }
}

// MARK: - iOS DeviceSupport

struct DeviceSupportScanner: Scanner {
    let category = CategoryID.deviceSupport

    struct Entry: Equatable {
        let name: String
        let model: String
        let version: String
    }

    /// Zerlegt Ordnernamen wie „iPhone14,2 18.1.1 (22B91)“ oder „18.1.1 (22B91)“.
    static func parse(_ name: String) -> Entry? {
        let tokens = name.split(separator: " ").map(String.init)
        guard let version = tokens.first(where: { $0.range(of: #"^\d+(\.\d+)+$"#, options: .regularExpression) != nil || Int($0) != nil }) else { return nil }
        let first = tokens.first ?? ""
        let model = (first != version && first.contains(",")) ? first : "Ohne Modellangabe"
        return Entry(name: name, model: model, version: version)
    }

    /// Pro Modell die neueste Version behalten. Liefert die Namen, die gelöscht werden sollen.
    static func namesToRemove(_ names: [String]) -> Set<String> {
        let entries = names.compactMap(parse)
        var remove = Set<String>()
        for (_, group) in Dictionary(grouping: entries, by: \.model) {
            guard let newest = group.max(by: { Version.isLess($0.version, $1.version) }) else { continue }
            for e in group where e.name != newest.name { remove.insert(e.name) }
        }
        return remove
    }

    func scan(_ rules: RuleSnapshot) async -> CategoryResult {
        var items: [CleanupItem] = []
        // iOS, watchOS, tvOS, visionOS, macOS DeviceSupport
        let folders = FS.children(of: rules.xcode).filter { $0.lastPathComponent.hasSuffix("DeviceSupport") }
        for folder in folders {
            let platform = folder.lastPathComponent.replacingOccurrences(of: " DeviceSupport", with: "")
            let children = FS.children(of: folder).filter { FS.isDirectory($0) }
            let remove = Self.namesToRemove(children.map(\.lastPathComponent))
            for child in children {
                let name = child.lastPathComponent
                let entry = Self.parse(name)
                let removing = remove.contains(name)
                items.append(CleanupItem(
                    category: category, url: child,
                    title: name,
                    detail: removing ? "Ältere \(platform)-Version – neuere für dieses Modell vorhanden" : "Neueste \(platform)-Version für dieses Modell – bleibt",
                    size: FS.allocatedSize(of: child),
                    method: .direct, preselected: removing,
                    groupKey: "\(platform) · \(entry?.model ?? "Unbekannt")"))
            }
        }
        return CategoryResult(category: category, items: items)
    }
}

// MARK: - Simulator-Geräte

struct SimulatorDevicesScanner: Scanner {
    let category = CategoryID.simulatorDevices

    struct Device: Decodable {
        let udid: String
        let name: String
        let isAvailable: Bool?
        let availabilityError: String?
        let dataPath: String?
        let dataPathSize: Int64?
        let lastBootedAt: String?
        let state: String?
    }
    struct Listing: Decodable { let devices: [String: [Device]] }

    func scan(_ rules: RuleSnapshot) async -> CategoryResult {
        let out = await Shell.run("/usr/bin/xcrun", ["simctl", "list", "devices", "-j"])
        guard out.ok, let listing = try? JSONDecoder().decode(Listing.self, from: Data(out.stdout.utf8)) else {
            return CategoryResult(category: category, items: [], notice: "Simulatoren konnten nicht gelesen werden (ist Xcode installiert?).")
        }
        let iso = ISO8601DateFormatter()
        let cutoff = Date().addingTimeInterval(-Double(rules.simulatorDays) * 86400)
        var items: [CleanupItem] = []
        for (runtime, devices) in listing.devices {
            let runtimeName = runtime.replacingOccurrences(of: "com.apple.CoreSimulator.SimRuntime.", with: "")
                .replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: #"(\d) (\d)"#, with: "$1.$2", options: .regularExpression)
            for d in devices {
                let deviceDir = d.dataPath.map { URL(fileURLWithPath: $0).deletingLastPathComponent() }
                let size = d.dataPathSize ?? deviceDir.map(FS.allocatedSize) ?? 0
                let unavailable = d.isAvailable == false
                let lastBoot = d.lastBootedAt.flatMap { iso.date(from: $0) }
                let stale = lastBoot.map { $0 < cutoff } ?? false
                // Nie gestartete, leere Geräte sind Xcodes Standardgeräte – die lassen wir in Ruhe.
                guard unavailable || stale || size > 50_000_000 else { continue }
                let booted = d.state == "Booted"
                let reason: String
                if unavailable { reason = "Nicht mehr verfügbar" + (d.availabilityError.map { " (\($0))" } ?? "") }
                else if let lastBoot { reason = "Zuletzt gestartet: \(lastBoot.formatted(date: .abbreviated, time: .omitted))" }
                else { reason = "Noch nie gestartet" }
                items.append(CleanupItem(
                    category: category, url: deviceDir,
                    title: d.name, detail: reason,
                    size: size,
                    method: .command(executable: "/usr/bin/xcrun", arguments: ["simctl", "delete", d.udid]),
                    preselected: (unavailable || stale) && !booted,
                    warning: booted ? "Läuft gerade" : nil,
                    groupKey: runtimeName, id: "sim:\(d.udid)"))
            }
        }
        return CategoryResult(category: category, items: items)
    }
}

// MARK: - Simulator-Runtimes

struct SimulatorRuntimesScanner: Scanner {
    let category = CategoryID.simulatorRuntimes

    struct Runtime: Decodable {
        let identifier: String
        let version: String?
        let build: String?
        let platformIdentifier: String?
        let sizeBytes: Int64?
        let deletable: Bool?
        let state: String?
        let lastUsedAt: String?
    }

    /// Liefert die IDs der Runtimes, die eine neuere Version derselben Plattform haben.
    static func outdated(_ runtimes: [Runtime]) -> Set<String> {
        var result = Set<String>()
        for (_, group) in Dictionary(grouping: runtimes, by: { $0.platformIdentifier ?? "?" }) {
            guard let newest = group.max(by: { Version.isLess($0.version ?? "0", $1.version ?? "0") }) else { continue }
            for r in group where r.identifier != newest.identifier && Version.isLess(r.version ?? "0", newest.version ?? "0") {
                result.insert(r.identifier)
            }
        }
        return result
    }

    func scan(_ rules: RuleSnapshot) async -> CategoryResult {
        let out = await Shell.run("/usr/bin/xcrun", ["simctl", "runtime", "list", "-j"])
        guard out.ok, let dict = try? JSONDecoder().decode([String: Runtime].self, from: Data(out.stdout.utf8)) else {
            return CategoryResult(category: category, items: [], notice: "Runtimes konnten nicht gelesen werden.")
        }
        let runtimes = Array(dict.values)
        let old = Self.outdated(runtimes)
        let items = runtimes.map { r -> CleanupItem in
            let platform = (r.platformIdentifier ?? "")
                .replacingOccurrences(of: "com.apple.platform.", with: "")
                .replacingOccurrences(of: "iphonesimulator", with: "iOS")
                .replacingOccurrences(of: "watchsimulator", with: "watchOS")
                .replacingOccurrences(of: "appletvsimulator", with: "tvOS")
                .replacingOccurrences(of: "xrsimulator", with: "visionOS")
            let isOld = old.contains(r.identifier)
            let canDelete = r.deletable != false
            return CleanupItem(
                category: category, url: nil,
                title: "\(platform) \(r.version ?? "?") (\(r.build ?? "?"))",
                detail: isOld ? "Neuere \(platform)-Runtime vorhanden" : "Neueste \(platform)-Runtime – bleibt",
                size: r.sizeBytes ?? 0,
                method: canDelete ? .command(executable: "/usr/bin/xcrun", arguments: ["simctl", "runtime", "delete", r.identifier]) : .infoOnly,
                preselected: isOld && canDelete,
                warning: canDelete ? nil : "Von Xcode geschützt",
                groupKey: platform, id: "runtime:\(r.identifier)")
        }
        return CategoryResult(category: category, items: items)
    }
}

// MARK: - DerivedData

struct DerivedDataScanner: Scanner {
    let category = CategoryID.derivedData

    func scan(_ rules: RuleSnapshot) async -> CategoryResult {
        let root = rules.xcode.appending(path: "DerivedData")
        let cutoff = Date().addingTimeInterval(-Double(rules.derivedDataDays) * 86400)
        var items: [CleanupItem] = []
        for folder in FS.children(of: root) where FS.isDirectory(folder) {
            let info = FS.plist(at: folder.appending(path: "info.plist"))
            let workspace = info?["WorkspacePath"] as? String
            let lastAccess = (info?["LastAccessedDate"] as? Date) ?? FS.modificationDate(folder)
            let orphan = workspace.map { !FS.fm.fileExists(atPath: $0) } ?? false
            let old = lastAccess.map { $0 < cutoff } ?? true
            let isModuleCache = folder.lastPathComponent == "ModuleCache.noindex"
            let projectName = workspace.map { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent }
                ?? folder.lastPathComponent.components(separatedBy: "-").first ?? folder.lastPathComponent
            var detail: String
            if isModuleCache { detail = "Gemeinsamer Modul-Cache" }
            else if orphan { detail = "Projekt existiert nicht mehr: \(FS.pretty(URL(fileURLWithPath: workspace!)))" }
            else if let lastAccess { detail = "Zuletzt gebaut: \(lastAccess.formatted(date: .abbreviated, time: .shortened))" }
            else { detail = "" }
            if !orphan, let workspace { detail += " · \(FS.pretty(URL(fileURLWithPath: workspace)))" }
            items.append(CleanupItem(
                category: category, url: folder,
                title: isModuleCache ? "ModuleCache" : projectName,
                detail: detail,
                size: FS.allocatedSize(of: folder),
                method: .direct,
                preselected: orphan || old,
                warning: orphan ? "Verwaist" : nil))
        }
        return CategoryResult(category: category, items: items)
    }
}

// MARK: - Archives

struct ArchivesScanner: Scanner {
    let category = CategoryID.archives

    struct Archive {
        let url: URL
        let app: String
        let bundleID: String
        let date: Date
        let version: String
    }

    /// Pro App die neuesten `keep` Archive behalten, den Rest liefern.
    static func toRemove(_ archives: [Archive], keep: Int) -> Set<URL> {
        var result = Set<URL>()
        for (_, group) in Dictionary(grouping: archives, by: \.bundleID) {
            let sorted = group.sorted { $0.date > $1.date }
            for a in sorted.dropFirst(max(keep, 0)) { result.insert(a.url) }
        }
        return result
    }

    func scan(_ rules: RuleSnapshot) async -> CategoryResult {
        let root = rules.xcode.appending(path: "Archives")
        var archives: [Archive] = []
        for day in FS.children(of: root) where FS.isDirectory(day) {
            for arch in FS.children(of: day) where arch.pathExtension == "xcarchive" {
                let info = FS.plist(at: arch.appending(path: "Info.plist")) ?? [:]
                let props = info["ApplicationProperties"] as? [String: Any] ?? [:]
                let name = info["Name"] as? String ?? arch.deletingPathExtension().lastPathComponent
                archives.append(Archive(
                    url: arch, app: name,
                    bundleID: props["CFBundleIdentifier"] as? String ?? name,
                    date: info["CreationDate"] as? Date ?? FS.modificationDate(arch) ?? .distantPast,
                    version: [props["CFBundleShortVersionString"] as? String, (props["CFBundleVersion"] as? String).map { "(\($0))" }]
                        .compactMap { $0 }.joined(separator: " ")))
            }
        }
        let remove = Self.toRemove(archives, keep: rules.archivesToKeep)
        let items = archives.map { a in
            CleanupItem(
                category: category, url: a.url,
                title: "\(a.app) \(a.version)".trimmingCharacters(in: .whitespaces),
                detail: "Archiviert am \(a.date.formatted(date: .abbreviated, time: .shortened))" + (remove.contains(a.url) ? "" : " · gehört zu den letzten \(rules.archivesToKeep)"),
                size: FS.allocatedSize(of: a.url),
                method: .trash,
                preselected: remove.contains(a.url),
                groupKey: a.app)
        }
        return CategoryResult(category: category, items: items)
    }
}

// MARK: - Xcode-Caches

struct XcodeCachesScanner: Scanner {
    let category = CategoryID.xcodeCaches

    func scan(_ rules: RuleSnapshot) async -> CategoryResult {
        let candidates: [(String, String)] = [
            ("Library/Developer/Xcode/UserData/Previews", "SwiftUI-Previews"),
            ("Library/Developer/Xcode/Products", "Xcode-Produkte (Testbuilds)"),
            ("Library/Developer/XCPGDevices", "Playground-Geräte"),
            ("Library/Developer/CoreSimulator/Caches", "Simulator-Cache"),
            ("Library/Caches/com.apple.dt.Xcode", "Xcode-Cache"),
            ("Library/Caches/org.swift.swiftpm", "Swift Package Manager – Cache"),
            ("Library/Developer/Xcode/DocumentationCache", "Dokumentations-Cache"),
            ("Library/Developer/Xcode/UserData/IB Support", "Interface-Builder-Cache"),
            ("Library/Logs/CoreSimulator", "Simulator-Logs"),
        ]
        let xcodeRunning = rules.runningBundleIDs.contains("com.apple.dt.Xcode")
        var items: [CleanupItem] = []
        for (rel, title) in candidates {
            let url = rules.home.appending(path: rel)
            guard FS.exists(url) else { continue }
            let size = FS.allocatedSize(of: url)
            guard size > 0 else { continue }
            items.append(CleanupItem(category: category, url: url, title: title, detail: FS.pretty(url),
                                     size: size, method: .direct, preselected: !xcodeRunning,
                                     warning: xcodeRunning ? "Xcode läuft – bitte zuerst beenden" : nil))
        }
        return CategoryResult(category: category, items: items,
                              notice: xcodeRunning ? "Xcode läuft gerade. Beende Xcode, bevor du Xcode-Caches löschst." : nil)
    }
}
