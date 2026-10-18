import AppKit
import SatsumaCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let monitor = DragMonitor()
    private let wheel = WheelPanel()
    private let ffmpeg = Converter.findFFmpeg()
    private var statusItem: NSStatusItem!
    private var busy = 0 {
        didSet { statusItem.button?.title = busy > 0 ? " \(busy)" : "" }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = Logo.menuBarImage()
        statusItem.button?.imagePosition = .imageLeading
        let menu = NSMenu()
        menu.addItem(Logo.menuHeader())
        menu.addItem(.separator())
        menu.addItem(withTitle: "Drag a file, then tap ⇧ Shift", action: nil, keyEquivalent: "")
        if ffmpeg == nil { menu.addItem(withTitle: "ffmpeg not found: video/audio disabled", action: nil, keyEquivalent: "") }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Allow All Folders (Full Disk Access)…", action: #selector(openFullDiskAccess),
                     keyEquivalent: "").target = self
        menu.addItem(withTitle: "Quit Satsuma", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu

        monitor.onTrigger = { [weak self] urls in self?.showWheel(for: urls) }
        monitor.onCancel = { [weak self] in self?.wheel.dismiss() }
        // Small delay so a drop that lands on mouse-up is delivered before the panel goes away.
        monitor.onRelease = { [weak self] in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self?.wheel.dismiss() }
        }
        monitor.start()
    }

    /// Full Disk Access means macOS never asks per folder. The user adds Satsuma there themselves.
    @objc private func openFullDiskAccess() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL]) // so it can be dragged into the list
    }

    private func showWheel(for urls: [URL]) {
        guard let category = Formats.category(of: urls[0]) else { NSSound.beep(); return }
        let files = urls.filter { Formats.category(of: $0) == category }
        let formats = Formats.targets(for: category, sourceExt: files[0].pathExtension)
        wheel.show(formats, at: NSEvent.mouseLocation) { [weak self] format in
            self?.convert(files, to: format, category: category)
        }
    }

    private func convert(_ files: [URL], to format: Format, category: FileCategory) {
        wheel.dismiss()
        busy += 1
        let ffmpeg = self.ffmpeg
        DispatchQueue.global(qos: .userInitiated).async {
            var outputs: [URL] = [], errors: [String] = []
            for file in files {
                do { outputs += try Converter.convert(file, to: format, category: category, ffmpeg: ffmpeg) }
                catch { errors.append("\(file.lastPathComponent): \(error.localizedDescription)") }
            }
            DispatchQueue.main.async {
                self.busy -= 1
                if !outputs.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(outputs) }
                if !errors.isEmpty { self.showError(errors.joined(separator: "\n\n")) }
            }
        }
    }

    private func showError(_ text: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Conversion failed"
        alert.informativeText = text
        alert.runModal()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
