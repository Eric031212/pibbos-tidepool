// Spike 6: launch at login.
// A tiny LSUIElement app that registers / unregisters itself with
// SMAppService.mainApp and logs every launch, so we can see whether the first
// registration needs any user action and whether macOS really starts it at
// login. Log: ~/Library/Logs/TidepoolLoginSpike.log (appended, survives logout).
// Arguments: register | unregister | status | (none = normal launch, e.g. at login).

import AppKit
import ServiceManagement

let timestampFormatter = ISO8601DateFormatter()
timestampFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
let logURL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Logs/TidepoolLoginSpike.log")

func log(_ message: String) {
    let line = "[\(timestampFormatter.string(from: Date()))] \(message)\n"
    print(line, terminator: "")
    if let handle = try? FileHandle(forWritingTo: logURL) {
        handle.seekToEndOfFile()
        handle.write(line.data(using: .utf8)!)
        try? handle.close()
    } else {
        try? line.write(to: logURL, atomically: true, encoding: .utf8)
    }
}

func statusName(_ status: SMAppService.Status) -> String {
    switch status {
    case .notRegistered: return "notRegistered"
    case .enabled: return "enabled"
    case .requiresApproval: return "requiresApproval"
    case .notFound: return "notFound"
    @unknown default: return "unknown(\(status.rawValue))"
    }
}

let service = SMAppService.mainApp
let command = CommandLine.arguments.dropFirst().first(where: { !$0.hasPrefix("-") }) ?? ""

log("LAUNCH pid=\(ProcessInfo.processInfo.processIdentifier) parent=\(getppid()) command='\(command)' "
    + "status=\(statusName(service.status)) systemUptime=\(Int(ProcessInfo.processInfo.systemUptime))s "
    + "path=\(Bundle.main.bundlePath)")

switch command {
case "register":
    do {
        try service.register()
        log("register() returned without error; status=\(statusName(service.status))")
    } catch {
        let nsError = error as NSError
        log("register() threw: \(nsError.domain) \(nsError.code) \(nsError.localizedDescription); status=\(statusName(service.status))")
    }
case "unregister":
    do {
        try service.unregister()
        log("unregister() returned without error; status=\(statusName(service.status))")
    } catch {
        let nsError = error as NSError
        log("unregister() threw: \(nsError.domain) \(nsError.code) \(nsError.localizedDescription); status=\(statusName(service.status))")
    }
case "status", "":
    break
default:
    log("unknown command")
}

// Stay up a few seconds so any notification or prompt can appear, re-check the
// status (it may settle asynchronously), then quit.
DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
    log("EXIT status=\(statusName(service.status))")
    NSApp.terminate(nil)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
app.run()
