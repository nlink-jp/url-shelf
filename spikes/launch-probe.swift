import AppKit

// Probe: can NSWorkspace.openApplication drive a browser into a private window,
// including when that browser is already running?
//
//   swift spikes/launch-probe.swift <bundleID> <url> <newInstance:0|1> [flag...]
//
// This is the harness behind the capability table in the README. A wrong private
// flag does not raise an error — it opens the URL in a NORMAL window, which is the
// one outcome this app exists to prevent. So the table is only ever settled by
// running this and *looking at the screen*; the flag's effect cannot be observed
// programmatically without Screen Recording permission, which the app must not need.
//
// Re-run it when a browser ships a major update, or when adding a browser.
//
// Measured 2026-07-26 (macOS 26.5.2, all three already running):
//   org.mozilla.firefox   -private-window   1  -> private window        OK
//   org.mozilla.firefox   --private-window  1  -> NORMAL window         silently wrong
//   com.google.Chrome     --incognito       1  -> incognito window      OK
//   com.microsoft.edgemac --inprivate       1  -> InPrivate window      OK
//   com.microsoft.edgemac --inprivate       0  -> nothing opened
//
// usage: swift launch-probe.swift <bundleID> <url> <newInstance:0|1> [flag...]

let argv = Array(CommandLine.arguments.dropFirst())
guard argv.count >= 3 else {
    print("usage: spike-launch.swift <bundleID> <url> <newInstance:0|1> [flag...]")
    exit(2)
}
let bundleID = argv[0]
let urlString = argv[1]
let newInstance = argv[2] == "1"
let flags = Array(argv.dropFirst(3))

guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
    print("FAIL: no app for bundle id \(bundleID)")
    exit(1)
}

let wasRunning = !NSRunningApplication
    .runningApplications(withBundleIdentifier: bundleID).isEmpty

let config = NSWorkspace.OpenConfiguration()
config.arguments = flags + [urlString]
config.createsNewApplicationInstance = newInstance
config.activates = true

print("app          : \(appURL.path)")
print("was running  : \(wasRunning)")
print("arguments    : \(config.arguments)")
print("new instance : \(newInstance)")

var finished = false
NSWorkspace.shared.openApplication(at: appURL, configuration: config) { app, error in
    if let error {
        print("RESULT: error — \(error.localizedDescription)")
    } else if let app {
        print("RESULT: ok — pid \(app.processIdentifier), \(app.bundleIdentifier ?? "?")")
    } else {
        print("RESULT: ok — no app handle returned")
    }
    finished = true
}

let deadline = Date().addingTimeInterval(20)
while !finished, Date() < deadline {
    RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.1))
}
if !finished { print("RESULT: timed out") }

// Report the instance count afterwards: forwarding to the existing process
// should leave exactly one running instance.
let after = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
print("instances now: \(after.count) — pids \(after.map(\.processIdentifier))")
