import AppKit

/// Polls at 10 Hz for "files are being dragged and the shortcut was just tapped".
/// Uses only state readable without Accessibility or Input Monitoring permission.
final class DragMonitor {
    var shortcut: NSEvent.ModifierFlags = .shift
    var onTrigger: (([URL]) -> Void)?
    var onCancel: (() -> Void)?
    var onRelease: (() -> Void)?

    private let dragPasteboard = NSPasteboard(name: .drag)
    private var timer: DispatchSourceTimer?
    private var baselineCount = 0
    private var wasDown = false
    private var wasHeld = false

    func start() {
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now(), repeating: 0.1, leeway: .milliseconds(20))
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume()
        timer = t
    }

    private func tick() {
        let source = CGEventSourceStateID.combinedSessionState
        let down = CGEventSource.buttonState(source, button: .left) || NSEvent.pressedMouseButtons & 1 != 0
        let mods = NSEvent.modifierFlags
            .union(NSEvent.ModifierFlags(rawValue: UInt(CGEventSource.flagsState(source).rawValue)))
            .intersection([.shift, .control, .option, .command])
        let held = mods == shortcut
        let count = dragPasteboard.changeCount
        defer { wasDown = down; wasHeld = held }

        guard down else {
            baselineCount = count // a drag that starts after this press bumps the count
            if wasDown { onRelease?() }
            return
        }
        if CGEventSource.keyState(source, key: 0x35) { // Escape
            baselineCount = count // suppress re-trigger until the next drag
            onCancel?()
            return
        }
        guard count != baselineCount, held, !wasHeld else { return }
        let urls = dragPasteboard.readObjects(forClasses: [NSURL.self],
                                              options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        if !urls.isEmpty { onTrigger?(urls) }
    }
}
