import Foundation

/// Letzte Sicherheitsprüfung vor jedem Löschen – unabhängig davon, was ein Scanner vorschlägt.
///
/// Regeln:
/// 1. Nur innerhalb des eigenen Benutzerordners.
/// 2. Nie wichtige Wurzelordner selbst (~, ~/Library, ~/Documents, ~/Downloads …).
/// 3. Nie etwas in oder über einem Pfad der Schutzliste.
/// 4. Nie in den Kernordnern der Fotos-Mediathek oder von iCloud Drive.
enum SafetyGuard {
    /// Ordner, die nie selbst gelöscht werden dürfen (Inhalte schon).
    static let protectedRoots: [String] = [
        "", "Library", "Documents", "Desktop", "Downloads", "Pictures", "Movies", "Music",
        "Developer", "Applications", "Public", ".Trash",
        "Library/Caches", "Library/Logs", "Library/Application Support", "Library/Preferences",
        "Library/Containers", "Library/Group Containers", "Library/Developer",
        "Library/Developer/Xcode", "Library/Developer/Xcode/DerivedData", "Library/Developer/Xcode/Archives",
        "Library/Developer/Xcode/iOS DeviceSupport", "Library/Developer/CoreSimulator",
        "Library/Mobile Documents", "Library/CloudStorage", "Library/Keychains", "Library/Mail", "Library/Messages",
    ]

    /// Teilpfade, in denen nie etwas gelöscht wird.
    static let forbiddenFragments: [String] = [
        ".photoslibrary", "/Library/Keychains", "/Library/Mobile Documents", "/Library/CloudStorage",
        "/Library/Mail/", "/Library/Messages/",
    ]

    enum Verdict: Equatable {
        case allowed
        case denied(String)
    }

    static func check(_ url: URL, home: URL, protectedPaths: [String]) -> Verdict {
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        let homePath = home.standardizedFileURL.resolvingSymlinksInPath().path

        guard path.hasPrefix(homePath + "/") else {
            return .denied("Liegt ausserhalb deines Benutzerordners")
        }
        let relative = String(path.dropFirst(homePath.count + 1))
        if protectedRoots.contains(relative) || relative.isEmpty {
            return .denied("Wichtiger Systemordner")
        }
        for f in forbiddenFragments where path.contains(f) {
            return .denied("Geschützter Bereich (\(f))")
        }
        for p in protectedPaths {
            let prot = URL(fileURLWithPath: p).standardizedFileURL.path
            // geschützt, wenn das Ziel in einem geschützten Ordner liegt ODER ihn enthält
            if path == prot || path.hasPrefix(prot + "/") || prot.hasPrefix(path + "/") {
                return .denied("Steht auf deiner Schutzliste")
            }
        }
        return .allowed
    }
}
