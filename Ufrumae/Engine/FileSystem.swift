import Foundation

/// Hilfsfunktionen rund um Dateien und Grössen.
enum FS {
    static let fm = FileManager.default

    /// Belegter Platz eines Ordners oder einer Datei in Bytes (so wie der Finder ihn zählt).
    /// Fehler (z. B. fehlende Rechte) werden still übersprungen.
    static func allocatedSize(of url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isDirectoryKey, .isSymbolicLinkKey]
        guard let values = try? url.resourceValues(forKeys: keys) else { return 0 }
        if values.isSymbolicLink == true { return 0 }
        if values.isDirectory != true {
            return Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }
        var total: Int64 = 0
        guard let e = fm.enumerator(at: url, includingPropertiesForKeys: Array(keys), options: [], errorHandler: { _, _ in true }) else { return 0 }
        for case let child as URL in e {
            guard let v = try? child.resourceValues(forKeys: keys), v.isRegularFile == true else { continue }
            total += Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
        }
        return total
    }

    /// Direkte Kinder eines Ordners (inkl. versteckter Dateien). Leeres Array, wenn nicht lesbar.
    static func children(of url: URL) -> [URL] {
        (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey], options: [])) ?? []
    }

    /// Wie `children`, wirft aber den Fehler weiter (um fehlende Rechte zu erkennen).
    static func childrenThrowing(of url: URL) throws -> [URL] {
        try fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey], options: [])
    }

    static func exists(_ url: URL) -> Bool { fm.fileExists(atPath: url.path) }

    static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    static func modificationDate(_ url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    /// „Zuletzt geöffnet“ laut Spotlight, sonst „Hinzugefügt“, sonst Änderungsdatum.
    static func lastUsedDate(_ url: URL) -> Date? {
        if let item = MDItemCreateWithURL(nil, url as CFURL) {
            if let d = MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date { return d }
            if let d = MDItemCopyAttribute(item, kMDItemDateAdded) as? Date { return d }
        }
        let v = try? url.resourceValues(forKeys: [.addedToDirectoryDateKey, .contentModificationDateKey])
        return v?.addedToDirectoryDate ?? v?.contentModificationDate
    }

    static func plist(at url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
    }

    /// Pfad mit „~“ statt Benutzerordner – für die Anzeige.
    static func pretty(_ url: URL) -> String {
        let home = fm.homeDirectoryForCurrentUser.path
        let p = url.path
        return p.hasPrefix(home) ? "~" + p.dropFirst(home.count) : p
    }

    /// Freier Speicher auf dem Startvolume (so wie macOS ihn für „wichtige“ Daten zählt).
    static func freeSpace() -> (free: Int64, total: Int64) {
        let url = fm.homeDirectoryForCurrentUser
        let v = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey])
        return (v?.volumeAvailableCapacityForImportantUsage ?? 0, Int64(v?.volumeTotalCapacity ?? 0))
    }

    /// Prüft, ob Ufrumä Festplattenvollzugriff hat. Die TCC-Datenbank ist nur damit lesbar.
    /// Ordner, die macOS ohne Festplattenvollzugriff hart sperrt (ohne Rückfrage).
    /// Der früher übliche Test über `TCC.db` ist unzuverlässig: Die Datei existiert
    /// nicht auf jedem Mac/jeder macOS-Version – dann meldete Ufrumä „fehlt“, obwohl erteilt.
    static let fullDiskAccessProbes = [
        "Library/Safari",
        "Library/Mail",
        "Library/Messages",
        "Library/Cookies",
        "Library/Containers/com.apple.Safari",
        ".Trash",
        "Library/Application Support/com.apple.TCC",
    ]

    static func hasFullDiskAccess() -> Bool {
        let home = fm.homeDirectoryForCurrentUser
        for rel in fullDiskAccessProbes {
            let url = home.appending(path: rel)
            // Existiert der Ordner nicht, sagt er nichts aus → nächster.
            if (try? fm.contentsOfDirectory(atPath: url.path)) != nil { return true }
        }
        return false
    }
}

extension Int64 {
    /// „12,3 GB“ – im Stil des Finders.
    var bytes: String { ByteCountFormatter.string(fromByteCount: self, countStyle: .file) }
}
