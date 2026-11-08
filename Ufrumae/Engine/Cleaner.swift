import Foundation

/// Führt das eigentliche Aufräumen aus.
struct Cleaner: Sendable {
    struct Outcome: Sendable {
        var freed: [CategoryID: Int64] = [:]
        var processed = 0
        var failures: [String] = []
        var failedIDs: Set<String> = []
    }

    let dryRun: Bool
    let home: URL
    let protectedPaths: [String]

    func clean(_ items: [CleanupItem], progress: @Sendable (Int, Int) -> Void = { _, _ in }) async -> Outcome {
        var outcome = Outcome()
        for (index, item) in items.enumerated() {
            progress(index, items.count)
            do {
                try await remove(item)
                outcome.freed[item.category, default: 0] += item.size
                outcome.processed += 1
            } catch {
                outcome.failures.append("\(item.title): \(error.localizedDescription)")
                outcome.failedIDs.insert(item.id)
            }
        }
        progress(items.count, items.count)
        return outcome
    }

    struct CleanError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private func remove(_ item: CleanupItem) async throws {
        if case .infoOnly = item.method { throw CleanError(message: "Nur zur Ansicht") }

        // Jede Datei-Operation geht durch die Sicherheitsprüfung.
        if let url = item.url {
            if case .denied(let reason) = SafetyGuard.check(url, home: home, protectedPaths: protectedPaths) {
                throw CleanError(message: "Übersprungen – \(reason)")
            }
        }

        if dryRun { return } // Probelauf: nur so tun als ob.

        switch item.method {
        case .direct:
            guard let url = item.url else { throw CleanError(message: "Kein Pfad") }
            guard FS.exists(url) else { return } // schon weg – auch gut
            try FS.fm.removeItem(at: url)
        case .trash:
            guard let url = item.url else { throw CleanError(message: "Kein Pfad") }
            guard FS.exists(url) else { return }
            try FS.fm.trashItem(at: url, resultingItemURL: nil)
        case .command(let exe, let args):
            let out = await Shell.run(exe, args)
            if !out.ok {
                let msg = out.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                throw CleanError(message: msg.isEmpty ? "Befehl fehlgeschlagen (\(out.status))" : msg)
            }
        case .infoOnly:
            break
        }
    }
}

/// Speichert den Verlauf als JSON in ~/Library/Application Support/Ufrumae/history.json.
enum HistoryStore {
    static var fileURL: URL {
        let dir = FS.fm.homeDirectoryForCurrentUser.appending(path: "Library/Application Support/Ufrumae")
        try? FS.fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: "history.json")
    }

    static func load() -> [HistoryEntry] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([HistoryEntry].self, from: data)) ?? []
    }

    static func save(_ entries: [HistoryEntry]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(entries) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
