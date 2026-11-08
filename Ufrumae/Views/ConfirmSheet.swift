import SwiftUI

/// Letzte Vorschau vor dem Aufräumen: was wird wie entfernt.
struct ConfirmSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let items = model.selectedItems()
        let byMethod = Dictionary(grouping: items) { $0.method.label }
        VStack(alignment: .leading, spacing: 16) {
            Text(model.prefs.dryRun ? "Probelauf starten?" : "Jetzt aufräumen?")
                .font(.title2.bold())
            if model.prefs.dryRun {
                Label("Probelauf: Es wird nichts gelöscht. Ufrumä prüft nur, was passieren würde.", systemImage: "eye.circle.fill")
                    .foregroundStyle(.blue)
            }

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                ForEach(CategoryID.allCases.filter { !model.selectedItems(in: $0).isEmpty }) { c in
                    GridRow {
                        Label(c.title, systemImage: c.symbol)
                        Text("\(model.selectedItems(in: c).count) Einträge").foregroundStyle(.secondary)
                        Text(model.selectedSize(in: c).bytes).monospacedDigit().gridColumnAlignment(.trailing)
                    }
                }
                Divider()
                GridRow {
                    Text("Total").bold()
                    Text("\(items.count) Einträge").foregroundStyle(.secondary)
                    Text(model.selectedSize().bytes).bold().monospacedDigit()
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                if let n = byMethod["Direkt"]?.count {
                    Label("\(n) × endgültig löschen (Caches, Build-Daten – werden neu erzeugt)", systemImage: "xmark.bin").foregroundStyle(.red)
                }
                if let n = byMethod["Papierkorb"]?.count {
                    Label("\(n) × in den Papierkorb (wiederherstellbar)", systemImage: "trash").foregroundStyle(.blue)
                }
                if let n = byMethod["Befehl"]?.count {
                    Label("\(n) × über Werkzeug (xcrun simctl, npm …)", systemImage: "terminal").foregroundStyle(.purple)
                }
            }
            .font(.callout)

            if !model.items(in: .caches).filter({ model.selection.contains($0.id) && $0.warning != nil }).isEmpty {
                Label("Einige ausgewählte Apps laufen noch. Beende sie am besten vorher.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange).font(.callout)
            }

            if model.cleaning {
                ProgressView(value: Double(model.cleanProgress.done), total: Double(max(model.cleanProgress.total, 1)))
                Text("\(model.cleanProgress.done) / \(model.cleanProgress.total)").font(.caption).foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("Abbrechen") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(model.cleaning)
                Button(model.prefs.dryRun ? "Probelauf starten" : "Aufräumen") {
                    model.clean()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(model.prefs.dryRun ? .blue : .red)
                .disabled(model.cleaning || items.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 520)
        .onChange(of: model.cleaning) { _, now in
            if !now { dismiss() }
        }
    }
}
