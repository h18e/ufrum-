import SwiftUI

@main
struct UfrumaeApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        Window("Ufrumä", id: "main") {
            MainView()
                .environment(model)
                .frame(minWidth: 900, minHeight: 560)
        }
        .defaultSize(width: 1100, height: 720)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Aufräumen") {
                Button("Alles scannen") { model.scan() }
                    .keyboardShortcut("r")
                    .disabled(model.isScanning)
                Button("Schnell-Scan") { model.scan(quick: true) }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                    .disabled(model.isScanning)
            }
        }

        MenuBarExtra {
            MenuBarView()
                .environment(model)
        } label: {
            Label(model.freeSpace.bytes, systemImage: model.isLowOnSpace ? "exclamationmark.triangle.fill" : "internaldrive")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}
