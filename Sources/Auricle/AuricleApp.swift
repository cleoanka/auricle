import AppKit
import SwiftUI

@main
enum AuricleMain {
    static func main() {
        if CommandLine.arguments.contains("--probe") {
            Probe.run()
            return
        }
        AuricleApp.main()
    }
}

struct AuricleApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var controller = AudioController()

    var body: some Scene {
        MenuBarExtra {
            MenuView()
                .environmentObject(controller)
        } label: {
            Image(systemName: "waveform")
        }
        .menuBarExtraStyle(.window)

        Window("Auricle Settings", id: "settings") {
            SettingsView()
                .environmentObject(controller)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
