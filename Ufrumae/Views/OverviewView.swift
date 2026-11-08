import SwiftUI

struct OverviewView: View {
    @Environment(AppModel.self) private var model
    @Binding var sidebar: SidebarItem?
    @Binding var confirming: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                DiskGauge()

                if let outcome = model.lastOutcome {
                    OutcomeCard(outcome: outcome, dryRun: model.lastOutcomeWasDryRun)
                }

                HStack(alignment: .firstTextBaseline) {
                    Text("Gefunden").font(.title2.bold())
                    Spacer()
                    if let last = model.lastScan {
                        Text("Letzter Scan: \(last.formatted(date: .omitted, time: .shortened))")
                            .foregroundStyle(.secondary).font(.callout)
                    }
                }

                ForEach(CategoryID.Group.allCases) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(group.rawValue).font(.headline).foregroundStyle(.secondary)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 12)], spacing: 12) {
                            ForEach(CategoryID.allCases.filter { $0.group == group }) { c in
                                CategoryCard(category: c) { sidebar = .category(c) }
                            }
                        }
                    }
                }

                HStack {
                    Spacer()
                    Button {
                        confirming = true
                    } label: {
                        Label(model.prefs.dryRun ? "Probelauf starten – \(model.selectedSize().bytes)" : "Jetzt aufräumen – \(model.selectedSize().bytes)",
                              systemImage: model.prefs.dryRun ? "eye" : "sparkles")
                            .padding(.horizontal, 12).padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(model.selectedItems().isEmpty || model.isScanning || model.cleaning)
                }
            }
            .padding(24)
        }
    }
}

struct DiskGauge: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let used = max(model.totalSpace - model.freeSpace, 0)
        let fraction = model.totalSpace > 0 ? Double(used) / Double(model.totalSpace) : 0
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(model.freeSpace.bytes) frei").font(.largeTitle.bold())
                Text("von \(model.totalSpace.bytes)").foregroundStyle(.secondary)
                Spacer()
                if model.selectedSize() > 0 {
                    Text("+ \(model.selectedSize().bytes) möglich")
                        .font(.title3.bold()).foregroundStyle(.green)
                }
            }
            ProgressView(value: fraction)
                .tint(model.isLowOnSpace ? .red : (fraction > 0.85 ? .orange : .accentColor))
            if model.isLowOnSpace {
                Label("Weniger als \(model.prefs.lowSpaceWarningGB) GB frei", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red).font(.callout)
            }
        }
        .padding(16)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct CategoryCard: View {
    @Environment(AppModel.self) private var model
    let category: CategoryID
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 12) {
                Image(systemName: category.symbol)
                    .font(.title2).frame(width: 32)
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(category.title).font(.headline)
                    subtitle.font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if model.scanning.contains(category) {
                    ProgressView().controlSize(.small)
                } else {
                    Text(sizeText).font(.title3.monospacedDigit().bold())
                        .foregroundStyle(category.isInfoOnly ? .secondary : .primary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(model.prefs.isEnabled(category) ? 1 : 0.45)
    }

    private var sizeText: String {
        guard model.results[category] != nil else { return "–" }
        return category.isInfoOnly ? (model.results[category]?.totalSize ?? 0).bytes : model.selectedSize(in: category).bytes
    }

    @ViewBuilder private var subtitle: some View {
        if !model.prefs.isEnabled(category) {
            Text("Beim Scan ausgeschaltet")
        } else if let r = model.results[category] {
            if r.notice != nil && r.items.isEmpty {
                Text(r.notice!).lineLimit(1)
            } else if category.isInfoOnly {
                Text("\(r.items.count) Einträge · nur Ansicht")
            } else {
                Text("\(model.selectedItems(in: category).count) von \(r.items.count) ausgewählt")
            }
        } else if model.scanning.contains(category) {
            Text("Wird gescannt …")
        } else {
            Text("Noch nicht gescannt")
        }
    }
}

struct OutcomeCard: View {
    let outcome: Cleaner.Outcome
    let dryRun: Bool

    var body: some View {
        let total = outcome.freed.values.reduce(0, +)
        VStack(alignment: .leading, spacing: 6) {
            Label(dryRun ? "Probelauf: \(total.bytes) würden frei (\(outcome.processed) Einträge)"
                         : "Fertig: \(total.bytes) freigegeben (\(outcome.processed) Einträge)",
                  systemImage: dryRun ? "eye.circle.fill" : "checkmark.circle.fill")
                .font(.headline)
                .foregroundStyle(dryRun ? .blue : .green)
            if !outcome.failures.isEmpty {
                DisclosureGroup("\(outcome.failures.count) Einträge nicht entfernt") {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(outcome.failures, id: \.self) { Text($0).font(.caption).textSelection(.enabled) }
                    }
                }
                .foregroundStyle(.orange)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background((dryRun ? Color.blue : Color.green).opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
    }
}
