import SwiftUI

@main
struct WebsiteImagePrepApp: App {
    init() {
        if let flagIndex = CommandLine.arguments.firstIndex(of: "--generate-icon"),
           CommandLine.arguments.indices.contains(flagIndex + 1) {
            do {
                try AppIconGenerator.writePNG(to: URL(fileURLWithPath: CommandLine.arguments[flagIndex + 1]))
                Darwin.exit(EXIT_SUCCESS)
            } catch {
                fputs("Icon generation failed: \(error.localizedDescription)\n", stderr)
                Darwin.exit(EXIT_FAILURE)
            }
        }
        if CommandLine.arguments.contains("--self-test") {
            do {
                try SelfTest.run()
                print("All Website Image Prep checks passed.")
                Darwin.exit(EXIT_SUCCESS)
            } catch {
                fputs("Self-test failed: \(error.localizedDescription)\n", stderr)
                Darwin.exit(EXIT_FAILURE)
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1380, height: 860)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Add Images…") {
                    NotificationCenter.default.post(name: .addImagesRequested, object: nil)
                }
                .keyboardShortcut("o")

                Button("Import Naming File…") {
                    NotificationCenter.default.post(name: .importNamesRequested, object: nil)
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])
            }
        }
    }
}

extension Notification.Name {
    static let addImagesRequested = Notification.Name("WebsiteImagePrep.addImagesRequested")
    static let importNamesRequested = Notification.Name("WebsiteImagePrep.importNamesRequested")
}
