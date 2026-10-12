import AppKit
import Content
import Strings

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: PetController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        LaunchAtLogin.registerOnFirstLaunch()
        do {
            guard let packURL = Bundle.main.url(forResource: "pibbo", withExtension: nil) else {
                throw SkinError.unreadable("pibbo")
            }
            let controller = try PetController(pack: SkinPack.load(from: packURL))
            controller.start()
            self.controller = controller
        } catch {
            NSLog("Tidepool: \(Strings.Errors.skinFailedToLoad) \(error)")
            NSApp.terminate(nil)
        }
    }
}
