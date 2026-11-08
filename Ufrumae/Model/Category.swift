import Foundation

/// Alle Bereiche, die Ufrumä prüft. Die Reihenfolge hier ist die Reihenfolge in der Seitenleiste.
enum CategoryID: String, CaseIterable, Identifiable, Codable, Sendable {
    // Xcode
    case deviceSupport
    case simulatorDevices
    case simulatorRuntimes
    case derivedData
    case archives
    case xcodeCaches
    // Allgemein
    case caches
    case logs
    case devToolCaches
    case trash
    case downloads
    // Analyse
    case largeFiles
    case duplicates
    case appLeftovers
    case iosBackups
    case localSnapshots

    var id: String { rawValue }

    enum Group: String, CaseIterable, Identifiable {
        case xcode = "Xcode"
        case general = "Allgemein"
        case analysis = "Analyse"
        var id: String { rawValue }
    }

    var group: Group {
        switch self {
        case .deviceSupport, .simulatorDevices, .simulatorRuntimes, .derivedData, .archives, .xcodeCaches:
            return .xcode
        case .caches, .logs, .devToolCaches, .trash, .downloads:
            return .general
        case .largeFiles, .duplicates, .appLeftovers, .iosBackups, .localSnapshots:
            return .analysis
        }
    }

    var title: String {
        switch self {
        case .deviceSupport: return "iOS DeviceSupport"
        case .simulatorDevices: return "Simulator-Geräte"
        case .simulatorRuntimes: return "Simulator-Runtimes"
        case .derivedData: return "DerivedData"
        case .archives: return "Archives"
        case .xcodeCaches: return "Xcode-Caches"
        case .caches: return "App-Caches"
        case .logs: return "Logs"
        case .devToolCaches: return "Entwickler-Caches"
        case .trash: return "Papierkorb"
        case .downloads: return "Alte Downloads"
        case .largeFiles: return "Grosse Dateien"
        case .duplicates: return "Doppelte Dateien"
        case .appLeftovers: return "Reste alter Apps"
        case .iosBackups: return "iPhone-Backups"
        case .localSnapshots: return "Lokale Snapshots"
        }
    }

    var symbol: String {
        switch self {
        case .deviceSupport: return "iphone.gen3"
        case .simulatorDevices: return "ipad.and.iphone"
        case .simulatorRuntimes: return "shippingbox"
        case .derivedData: return "hammer"
        case .archives: return "archivebox"
        case .xcodeCaches: return "swift"
        case .caches: return "internaldrive"
        case .logs: return "doc.text"
        case .devToolCaches: return "terminal"
        case .trash: return "trash"
        case .downloads: return "arrow.down.circle"
        case .largeFiles: return "externaldrive.badge.exclamationmark"
        case .duplicates: return "doc.on.doc"
        case .appLeftovers: return "puzzlepiece.extension"
        case .iosBackups: return "iphone.and.arrow.forward"
        case .localSnapshots: return "clock.arrow.circlepath"
        }
    }

    /// Kurze Erklärung, was hier gefunden wird und nach welcher Regel.
    func explanation(_ p: RuleSnapshot) -> String {
        switch self {
        case .deviceSupport:
            return "Symbol-Daten, die Xcode für jedes angeschlossene iPhone anlegt. Pro Gerätemodell bleibt nur die neueste iOS-Version, ältere werden gelöscht. Xcode lädt Fehlendes beim nächsten Anschliessen automatisch neu."
        case .simulatorDevices:
            return "Simulatoren, die nicht mehr verfügbar sind oder seit \(p.simulatorDays) Tagen nicht gestartet wurden. Gelöscht wird über „xcrun simctl delete“."
        case .simulatorRuntimes:
            return "Simulator-Systeme (iOS, watchOS …). Ältere Versionen werden entfernt, wenn eine neuere derselben Plattform installiert ist. Gelöscht wird über „xcrun simctl runtime delete“."
        case .derivedData:
            return "Zwischenstände von Xcode-Builds. Vorgewählt sind Projekte, die seit \(p.derivedDataDays) Tagen nicht gebaut wurden, und Ordner, deren Projekt nicht mehr existiert. Wird beim nächsten Build neu erzeugt."
        case .archives:
            return "Archivierte App-Versionen inkl. dSYMs (nötig, um Crashberichte zu lesen). Pro App bleiben die letzten \(p.archivesToKeep), ältere gehen in den Papierkorb."
        case .xcodeCaches:
            return "SwiftUI-Previews, Xcode- und SwiftPM-Caches. Werden bei Bedarf neu erzeugt."
        case .caches:
            return "Zwischenspeicher deiner Apps in ~/Library/Caches. Fremd-Apps sind vorgewählt, Apple-eigene nur zur Ansicht. Läuft eine App, bitte zuerst beenden."
        case .logs:
            return "Protokolldateien in ~/Library/Logs. Werden von den Apps bei Bedarf neu geschrieben."
        case .devToolCaches:
            return "Paket-Caches von npm, pip, Yarn, CocoaPods, Gradle. Wo möglich über den offiziellen Befehl geleert."
        case .trash:
            return "Inhalt des Papierkorbs. Wird endgültig gelöscht."
        case .downloads:
            return "Dateien in „Downloads“, die seit \(p.downloadsDays) Tagen nicht geöffnet wurden. Gehen in den Papierkorb."
        case .largeFiles:
            return "Dateien ab \(p.largeFileGB.formatted()) GB in deinem Benutzerordner (ohne Library, Fotos-Mediathek und iCloud). Nichts ist vorgewählt."
        case .duplicates:
            return "Inhaltlich identische Dateien ab \(p.duplicateMinMB) MB (SHA-256-Vergleich). Die älteste Kopie bleibt, die anderen sind vorgewählt und gehen in den Papierkorb."
        case .appLeftovers:
            return "Einstellungen und Daten von Apps, die nicht mehr installiert sind. Nie vorgewählt – bitte einzeln prüfen. Gehen in den Papierkorb."
        case .iosBackups:
            return "Lokale iPhone/iPad-Backups. Nur zur Ansicht – löschen bitte über Finder → Gerät → Backups verwalten."
        case .localSnapshots:
            return "Lokale Time-Machine-Snapshots. Nur zur Ansicht – macOS entfernt sie automatisch, wenn Platz gebraucht wird."
        }
    }

    /// Bereiche, die nur anzeigen und nie löschen.
    var isInfoOnly: Bool {
        self == .iosBackups || self == .localSnapshots
    }

    /// Aufwändige Bereiche, die der Schnell-Scan in der Menüleiste auslässt.
    var isSlow: Bool {
        self == .largeFiles || self == .duplicates
    }
}
