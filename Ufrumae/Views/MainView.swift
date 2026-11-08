import SwiftUI

enum SidebarItem: Hashable {
    case overview
    case category(CategoryID)
    case history
}

struct MainView: View {
    @Environment(AppModel.self) private var model
    @State private var sidebar: SidebarItem? = .overview
    @State private var confirming = false

    var body: some View {
        NavigationSplitView {
            List(selection: $sidebar) {
                Label("Übersicht", systemImage: "gauge.with.dots.needle.67percent")
                    .tag(SidebarItem.overview)
                ForEach(CategoryID.Group.allCases) { group in
                    Section(group.rawValue) {
                        ForEach(CategoryID.allCases.filter { $0.group == group }) { c in
                            SidebarRow(category: c).tag(SidebarItem.category(c))
                        }
                    }
                }
                Section {
                    Label("Verlauf", systemImage: "clock").tag(SidebarItem.history)
                }
            }
            .navigationSplitViewColumnWidth(min: 230, ideal: 250)
        } detail: {
            VStack(spacing: 0) {
                if !model.hasFullDiskAccess { FullDiskAccessBanner() }
                if model.prefs.dryRun { DryRunBanner() }
                switch sidebar {
                case .category(let c): CategoryDetailView(category: c)
                case .history: HistoryView()
                default: OverviewView(sidebar: $sidebar, confirming: $confirming)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    sidebar = .overview
                } label: {
                    Label("Übersicht", systemImage: "chevron.backward")
                }
                .keyboardShortcut("[", modifiers: .command)
                .disabled(sidebar == .overview || sidebar == nil)
                .help("Zurück zur Übersicht (⌘[)")
            }
            ToolbarItemGroup {
                if model.isScanning {
                    ProgressView().controlSize(.small)
                }
                Button {
                    model.scan()
                } label: {
                    Label("Scannen", systemImage: "magnifyingglass")
                }
                .disabled(model.isScanning || model.cleaning)
                .help("Alle aktivierten Bereiche scannen (⌘R)")

                Button {
                    confirming = true
                } label: {
                    Label(model.prefs.dryRun ? "Probelauf (\(model.selectedSize().bytes))" : "Aufräumen (\(model.selectedSize().bytes))",
                          systemImage: model.prefs.dryRun ? "eye" : "sparkles")
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.selectedItems().isEmpty || model.isScanning || model.cleaning)
            }
        }
        .sheet(isPresented: $confirming) {
            ConfirmSheet()
        }
        .onAppear {
            // Beim Starten automatisch scannen – aber nicht, wenn die App nur als Test-Host läuft.
            let isTestHost = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            // Ohne Festplattenvollzugriff würde macOS den Scan mit Rückfragen anhalten → dann nur manuell.
            if model.results.isEmpty && !isTestHost && model.hasFullDiskAccess { model.scan() }
        }
    }
}

struct SidebarRow: View {
    @Environment(AppModel.self) private var model
    let category: CategoryID

    var body: some View {
        HStack {
            Label(category.title, systemImage: category.symbol)
            Spacer()
            if model.scanning.contains(category) {
                ProgressView().controlSize(.mini)
            } else if !model.prefs.isEnabled(category) {
                Text("aus").font(.caption).foregroundStyle(.tertiary)
            } else if let r = model.results[category] {
                let size = category.isInfoOnly ? r.totalSize : model.selectedSize(in: category)
                if size > 0 {
                    Text(size.bytes)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(category.isInfoOnly ? .secondary : .primary)
                }
            }
        }
    }
}

struct FullDiskAccessBanner: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.shield").font(.title2).foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Festplattenvollzugriff fehlt").bold()
                Text("Ohne ihn sieht Ufrumä z. B. den Papierkorb und die Daten anderer Apps nicht. Systemeinstellungen → Datenschutz & Sicherheit → Festplattenvollzugriff → Ufrumä einschalten, dann Ufrumä neu starten.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Einstellungen öffnen") { model.openFullDiskAccessSettings() }
            Button("Erneut prüfen") { model.refreshDiskInfo() }
        }
        .padding(12)
        .background(.orange.opacity(0.12))
    }
}

struct DryRunBanner: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "eye.circle.fill").foregroundStyle(.blue)
            Text("Probelauf ist aktiv – es wird nichts gelöscht, nur angezeigt, was passieren würde.")
                .font(.callout)
            Spacer()
            Button("Probelauf beenden") { model.prefs.dryRun = false }
                .controlSize(.small)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.blue.opacity(0.10))
    }
}
