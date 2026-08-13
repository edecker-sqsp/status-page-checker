import AppKit

if CommandLine.arguments.contains("--self-check") {
    SelfCheck.run()
}

let delegate = AppDelegate()
let app = NSApplication.shared
app.delegate = delegate
// Belt-and-suspenders alongside Info.plist's LSUIElement: no Dock icon, no
// app switcher entry, no menu bar menu bar (just our status item).
app.setActivationPolicy(.accessory)
app.run()
