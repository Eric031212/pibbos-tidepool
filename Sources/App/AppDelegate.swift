import AppKit
import Content
import Strings

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: PetController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        LaunchAtLogin.registerOnFirstLaunch()
        let bundle = Bundle.main
        do {
            guard let skin = bundle.url(forResource: "pibbo", withExtension: nil),
                  let ui = bundle.url(forResource: "UI", withExtension: nil) else {
                throw SkinError.unreadable("bundled resources")
            }
            let resources = PetController.Resources(
                skin: skin, ui: ui,
                music: bundle.url(forResource: "Music", withExtension: nil),
                zoneTab: bundle.url(forResource: "zone", withExtension: "tab"))
            // `--demo`: everything sped up, for trying Tidepool out.
            let controller = try PetController(resources: resources, demo: CommandLine.arguments.contains("--demo"))
            controller.start()
            self.controller = controller
        } catch {
            NSLog("Tidepool: \(Strings.Errors.skinFailedToLoad) \(error)")
            NSApp.terminate(nil)
        }
    }
}
