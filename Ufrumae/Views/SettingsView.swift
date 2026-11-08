import SwiftUI
import AppKit

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("Allgemein", systemImage: "gearshape") }
            RuleSettings().tabItem { Label("Regeln", systemImage: "slider.horizontal.3") }
            ProtectionSettings().tabItem { Label("Schutzliste", systemImage: "lock") }
        }
        .frame(width: 560, height: 440)
    }
}

private struct GeneralSettings: View {
    @Environment(AppModel.self) private var model
    @State private var launchAtLogin = false

    var body: some View {
        @Bindable var prefs = model.prefs
        Form {
            Section {
                Toggle("Probelauf – nichts wirklich löschen", isOn: $prefs.dryRun)
                Text("Solange der Probelauf aktiv ist, zeigt Ufrumä nur, was gelöscht würde. Ideal, um die Regeln zuerst zu prüfen.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Menüleiste") {
                Toggle("Ufrumä beim Anmelden starten", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, v in model.prefs.launchAtLogin = v }
                Stepper("Warnen unter \(prefs.lowSpaceWarningGB) GB freiem Speicher", value: $prefs.lowSpaceWarningGB, in: 5...200, step: 5)
            }
            Section("Berechtigung") {
                HStack {
                    Image(systemName: model.hasFullDiskAccess ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                        .foregroundStyle(model.hasFullDiskAccess ? .green : .orange)
                    Text(model.hasFullDiskAccess ? "Festplattenvollzugriff ist erteilt" : "Festplattenvollzugriff fehlt")
                    Spacer()
                    Button("Systemeinstellungen öffnen") { model.openFullDiskAccessSettings() }
                    Button("Prüfen") { model.refreshDiskInfo() }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { launchAtLogin = model.prefs.launchAtLogin }
    }
}

private struct RuleSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var prefs = model.prefs
        Form {
            Section("Xcode") {
                Stepper("DerivedData: älter als \(prefs.derivedDataDays) Tage", value: $prefs.derivedDataDays, in: 1...365)
                Stepper("Simulatoren: seit \(prefs.simulatorDays) Tagen nicht gestartet", value: $prefs.simulatorDays, in: 7...730, step: 7)
                Stepper("Archives: letzte \(prefs.archivesToKeep) pro App behalten", value: $prefs.archivesToKeep, in: 1...50)
            }
            Section("Dateien") {
                Stepper("Downloads: seit \(prefs.downloadsDays) Tagen nicht geöffnet", value: $prefs.downloadsDays, in: 7...730, step: 7)
                Stepper("Grosse Dateien: ab \(prefs.largeFileGB.formatted()) GB", value: $prefs.largeFileGB, in: 0.1...50, step: 0.5)
                Stepper("Duplikate: ab \(prefs.duplicateMinMB) MB", value: $prefs.duplicateMinMB, in: 1...1000)
            }
            Section {
                Text("Änderungen gelten beim nächsten Scan.").font(.caption).foregroundStyle(.secondary)
                if !prefs.ignoredIDs.isEmpty {
                    HStack {
                        Text("\(prefs.ignoredIDs.count) Einträge werden immer ignoriert")
                        Spacer()
                        Button("Zurücksetzen") { prefs.ignoredIDs = [] }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct ProtectionSettings: View {
    @Environment(AppModel.self) private var model
    @State private var selected: String?

    var body: some View {
        @Bindable var prefs = model.prefs
        VStack(alignment: .leading, spacing: 8) {
            Text("Ordner und Dateien auf dieser Liste schlägt Ufrumä nie zum Löschen vor – auch nicht das, was darin liegt.")
                .font(.callout).foregroundStyle(.secondary)
            List(prefs.protectedPaths, id: \.self, selection: $selected) { path in
                Label(FS.pretty(URL(fileURLWithPath: path)), systemImage: "lock.fill")
            }
            .listStyle(.bordered)
            HStack {
                Button {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true
                    panel.canChooseFiles = true
                    panel.allowsMultipleSelection = true
                    panel.prompt = "Schützen"
                    if panel.runModal() == .OK {
                        for url in panel.urls { model.protect(url) }
                    }
                } label: { Image(systemName: "plus") }
                Button {
                    if let s = selected { prefs.protectedPaths.removeAll { $0 == s } }
                    selected = nil
                } label: { Image(systemName: "minus") }
                    .disabled(selected == nil)
                Spacer()
            }
        }
        .padding(20)
    }
}
