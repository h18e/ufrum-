import SwiftUI
import AppKit

struct CategoryDetailView: View {
    @Environment(AppModel.self) private var model
    let category: CategoryID

    private var groups: [(key: String, items: [CleanupItem])] {
        let items = model.items(in: category)
        let grouped = Dictionary(grouping: items) { $0.groupKey ?? "" }
        return grouped.map { (key: $0.key, items: $0.value) }
            .sorted { $0.items.reduce(0) { $0 + $1.size } > $1.items.reduce(0) { $0 + $1.size } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if model.scanning.contains(category) {
                Spacer()
                HStack { Spacer(); ProgressView("Wird gescannt …"); Spacer() }
                Spacer()
            } else if model.results[category] == nil {
                ContentUnavailableView {
                    Label("Noch nicht gescannt", systemImage: category.symbol)
                } actions: {
                    Button("Diesen Bereich scannen") { model.scan([category]) }
                        .disabled(model.isScanning)
                }
            } else {
                List {
                    if let overview = model.results[category]?.overview, !overview.isEmpty {
                        Section("Wo steckt der Platz? (Benutzerordner)") {
                            FolderOverview(folders: overview)
                        }
                    }
                    if model.items(in: category).isEmpty {
                        Text("Nichts gefunden – hier ist alles sauber. ✨").foregroundStyle(.secondary)
                    }
                    ForEach(groups, id: \.key) { group in
                        if group.key.isEmpty {
                            ForEach(group.items) { ItemRow(item: $0) }
                        } else {
                            Section {
                                ForEach(group.items) { ItemRow(item: $0) }
                            } header: {
                                HStack {
                                    Text(group.key)
                                    Spacer()
                                    Text(group.items.reduce(0) { $0 + $1.size }.bytes).monospacedDigit()
                                }
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle(category.title)
    }

    private var header: some View {
        @Bindable var prefs = model.prefs
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Image(systemName: category.symbol).font(.largeTitle).foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 4) {
                    Text(category.title).font(.title.bold())
                    Text(category.explanation(model.rules()))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(category.isInfoOnly ? (model.results[category]?.totalSize ?? 0).bytes : model.selectedSize(in: category).bytes)
                        .font(.title2.bold().monospacedDigit())
                    Text(category.isInfoOnly ? "gesamt" : "ausgewählt").font(.caption).foregroundStyle(.secondary)
                }
            }
            if let notice = model.results[category]?.notice {
                Label(notice, systemImage: "info.circle")
                    .font(.callout).foregroundStyle(.orange)
            }
            HStack {
                Toggle("Beim Scan einbeziehen", isOn: Binding(
                    get: { model.prefs.isEnabled(category) },
                    set: { model.prefs.setEnabled(category, $0) }))
                    .toggleStyle(.switch).controlSize(.small)
                Spacer()
                if !category.isInfoOnly && !model.items(in: category).isEmpty {
                    Button("Alle wählen") { model.setAll(true, in: category) }
                    Button("Keine") { model.setAll(false, in: category) }
                }
                Button {
                    model.scan([category])
                } label: { Label("Neu scannen", systemImage: "arrow.clockwise") }
                    .disabled(model.isScanning)
            }
            .controlSize(.small)
        }
        .padding(16)
    }
}

struct ItemRow: View {
    @Environment(AppModel.self) private var model
    let item: CleanupItem

    var body: some View {
        HStack(spacing: 10) {
            if item.method != .infoOnly {
                Toggle("", isOn: Binding(get: { model.selection.contains(item.id) }, set: { _ in model.toggle(item) }))
                    .labelsHidden()
                    .toggleStyle(.checkbox)
            } else {
                Image(systemName: "eye").foregroundStyle(.secondary).frame(width: 16)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).lineLimit(1).truncationMode(.middle)
                if !item.detail.isEmpty {
                    Text(item.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
                if let w = item.warning {
                    Label(w, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
            Spacer()
            Label(item.method.label, systemImage: item.method.symbol)
                .font(.caption)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(badgeColor.opacity(0.15), in: Capsule())
                .foregroundStyle(badgeColor)
            Text(item.size > 0 ? item.size.bytes : "–")
                .monospacedDigit()
                .frame(width: 80, alignment: .trailing)
        }
        .contentShape(Rectangle())
        .onTapGesture { model.toggle(item) }
        .contextMenu {
            if let url = item.url, FS.exists(url) {
                Button("Im Finder zeigen") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                Button("Pfad kopieren") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url.path, forType: .string)
                }
                Divider()
                Button("Ordner/Datei schützen (Schutzliste)") { model.protect(url) }
            }
            Button("Immer ignorieren") { model.ignore(item) }
        }
        .help(item.url?.path ?? item.title)
    }

    private var badgeColor: Color {
        switch item.method {
        case .direct: return .red
        case .trash: return .blue
        case .command: return .purple
        case .infoOnly: return .gray
        }
    }
}

struct FolderOverview: View {
    let folders: [FolderUsage]

    var body: some View {
        let maxSize = max(folders.first?.size ?? 1, 1)
        VStack(alignment: .leading, spacing: 6) {
            ForEach(folders.prefix(15)) { f in
                HStack {
                    Text(FS.pretty(f.url)).lineLimit(1).frame(width: 260, alignment: .leading)
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.accentColor.gradient)
                            .frame(width: max(2, geo.size.width * CGFloat(Double(f.size) / Double(maxSize))))
                    }
                    .frame(height: 12)
                    Text(f.size.bytes).monospacedDigit().frame(width: 80, alignment: .trailing)
                }
                .contextMenu {
                    Button("Im Finder zeigen") { NSWorkspace.shared.activateFileViewerSelecting([f.url]) }
                }
            }
        }
        .padding(.vertical, 4)
    }
}
