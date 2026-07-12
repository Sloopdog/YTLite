import SwiftUI

@main
struct YTLiteApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 980, minHeight: 680)
        }
        .defaultSize(width: 1180, height: 780)
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
        .commands {
            CommandGroup(after: .newItem) {
                Button("Paste URL") {
                    model.pasteURL()
                }
                .keyboardShortcut("v", modifiers: [.command, .shift])

                Button("Start Queue") {
                    model.startQueue()
                }
                .keyboardShortcut(.return, modifiers: [.command])
            }
        }

        Settings {
            SettingsView()
                .environmentObject(model)
                .frame(width: 700, height: 560)
        }
    }
}
