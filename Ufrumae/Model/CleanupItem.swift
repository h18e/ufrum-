import Foundation

/// Wie ein Eintrag entfernt wird.
enum DeletionMethod: Codable, Hashable, Sendable {
    /// Endgültig löschen (Caches, Build-Daten – werden ohnehin neu erzeugt).
    case direct
    /// In den Papierkorb legen (alles Persönliche oder Unersetzliche).
    case trash
    /// Über ein offizielles Kommandozeilen-Werkzeug entfernen (z. B. `xcrun simctl delete`).
    case command(executable: String, arguments: [String])
    /// Wird nur angezeigt, nie gelöscht.
    case infoOnly

    var label: String {
        switch self {
        case .direct: return "Direkt"
        case .trash: return "Papierkorb"
        case .command: return "Befehl"
        case .infoOnly: return "Nur Ansicht"
        }
    }

    var symbol: String {
        switch self {
        case .direct: return "xmark.bin"
        case .trash: return "trash"
        case .command: return "terminal"
        case .infoOnly: return "eye"
        }
    }
}

/// Ein einzelner Fund, der gelöscht werden kann.
struct CleanupItem: Identifiable, Hashable, Sendable {
    let id: String
    let category: CategoryID
    /// Pfad auf der Festplatte (für „Im Finder zeigen“ und die Schutzliste). Bei Befehlen optional.
    let url: URL?
    let title: String
    let detail: String
    let size: Int64
    let method: DeletionMethod
    /// Ob der Eintrag in der Vorschau schon angehakt ist.
    var preselected: Bool
    /// Hinweis, der neben dem Eintrag angezeigt wird (z. B. „App läuft“).
    var warning: String?
    /// Zum Gruppieren in der Liste (z. B. Gerätemodell, App-Name, Duplikat-Gruppe).
    var groupKey: String?

    init(category: CategoryID,
         url: URL?,
         title: String,
         detail: String = "",
         size: Int64,
         method: DeletionMethod,
         preselected: Bool,
         warning: String? = nil,
         groupKey: String? = nil,
         id: String? = nil) {
        self.category = category
        self.url = url
        self.title = title
        self.detail = detail
        self.size = size
        self.method = method
        self.preselected = preselected
        self.warning = warning
        self.groupKey = groupKey
        self.id = id ?? "\(category.rawValue):\(url?.path ?? title)"
    }
}

/// Ergebnis eines Bereichs nach dem Scan.
struct CategoryResult: Sendable {
    let category: CategoryID
    var items: [CleanupItem]
    /// Hinweis zum ganzen Bereich (z. B. „Festplattenvollzugriff fehlt“).
    var notice: String?
    /// Zusätzliche Übersicht (nur „Grosse Dateien“: Ordnergrössen im Benutzerordner).
    var overview: [FolderUsage] = []
    var duration: TimeInterval = 0

    var totalSize: Int64 { items.reduce(0) { $0 + $1.size } }
}

struct FolderUsage: Identifiable, Hashable, Sendable {
    var id: String { url.path }
    let url: URL
    let size: Int64
}

/// Zusammenfassung der Einstellungen, die die Scanner brauchen.
/// Als Wert-Typ, damit Scanner im Hintergrund laufen können, ohne auf die Oberfläche zuzugreifen.
struct RuleSnapshot: Sendable {
    var derivedDataDays = 14
    var simulatorDays = 60
    var archivesToKeep = 3
    var downloadsDays = 90
    var largeFileGB: Double = 1
    var duplicateMinMB = 1
    var protectedPaths: [String] = []
    var ignoredIDs: Set<String> = []
    var home: URL = FileManager.default.homeDirectoryForCurrentUser
    var runningBundleIDs: Set<String> = []
    var runningAppNames: Set<String> = []
}

/// Ein Eintrag im Verlauf.
struct HistoryEntry: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    let date: Date
    let dryRun: Bool
    let perCategory: [String: Int64]
    let itemCount: Int
    let failures: [String]

    var total: Int64 { perCategory.values.reduce(0, +) }
}
