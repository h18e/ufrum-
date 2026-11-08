import SwiftUI

struct HistoryView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmClear = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading) {
                    Text("Verlauf").font(.title.bold())
                    Text("Bisher freigegeben: \(model.totalFreedEver.bytes)").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Verlauf leeren") { confirmClear = true }
                    .disabled(model.history.isEmpty)
            }
            .padding(16)
            Divider()
            if model.history.isEmpty {
                ContentUnavailableView("Noch nichts aufgeräumt", systemImage: "clock")
            } else {
                List(model.history) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(entry.date.formatted(date: .abbreviated, time: .shortened)).bold()
                            if entry.dryRun {
                                Text("Probelauf").font(.caption).padding(.horizontal, 6).background(.blue.opacity(0.15), in: Capsule())
                            }
                            Spacer()
                            Text(entry.total.bytes).bold().monospacedDigit()
                        }
                        Text(entry.perCategory.sorted { $0.value > $1.value }
                            .map { "\(CategoryID(rawValue: $0.key)?.title ?? $0.key): \($0.value.bytes)" }
                            .joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary)
                        if !entry.failures.isEmpty {
                            DisclosureGroup("\(entry.failures.count) nicht entfernt") {
                                ForEach(entry.failures, id: \.self) { Text($0).font(.caption).textSelection(.enabled) }
                            }
                            .font(.caption).foregroundStyle(.orange)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .confirmationDialog("Verlauf wirklich leeren?", isPresented: $confirmClear) {
            Button("Leeren", role: .destructive) { model.clearHistory() }
        }
    }
}
