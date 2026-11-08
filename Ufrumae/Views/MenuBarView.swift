import SwiftUI

struct MenuBarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "internaldrive").font(.title2)
                VStack(alignment: .leading) {
                    Text("\(model.freeSpace.bytes) frei").font(.title3.bold())
                    Text("von \(model.totalSpace.bytes)").font(.caption).foregroundStyle(.secondary)
                }
            }
            ProgressView(value: model.totalSpace > 0 ? Double(model.totalSpace - model.freeSpace) / Double(model.totalSpace) : 0)
                .tint(model.isLowOnSpace ? .red : .accentColor)

            if model.isLowOnSpace {
                Label("Weniger als \(model.prefs.lowSpaceWarningGB) GB frei", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red).font(.callout)
            }

            Divider()

            if model.isScanning {
                HStack { ProgressView().controlSize(.small); Text("Scanne …") }
            } else if model.lastScan != nil {
                Text("Aufräumbar: \(model.selectedSize().bytes)").font(.headline)
                ForEach(CategoryID.allCases.filter { model.selectedSize(in: $0) > 0 }.prefix(6)) { c in
                    HStack {
                        Label(c.title, systemImage: c.symbol).font(.callout)
                        Spacer()
                        Text(model.selectedSize(in: c).bytes).font(.callout.monospacedDigit())
                    }
                }
            }

            HStack {
                Button("Schnell-Scan") { model.scan(quick: true) }
                    .disabled(model.isScanning || model.cleaning)
                Spacer()
                Button("Ufrumä öffnen") {
                    openWindow(id: "main")
                    NSApp.activate()
                }
                .buttonStyle(.borderedProminent)
            }
            Divider()
            Button("Beenden") { NSApp.terminate(nil) }
                .buttonStyle(.plain).foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(width: 300)
        .onAppear { model.refreshDiskInfo() }
    }
}
