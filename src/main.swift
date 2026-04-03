import AppKit

private let bundleIdentifier = "local.displaykeys"

extension Notification.Name {
    static let displayKeysMoveLeft = Notification.Name("DisplayKeysMoveLeft")
    static let displayKeysMoveRight = Notification.Name("DisplayKeysMoveRight")
    static let displayKeysQuit = Notification.Name("DisplayKeysQuit")
}

enum Mode {
    case open
    case left
    case right
    case quit

    init?(argument: String?) {
        switch argument?.lowercased() {
        case nil, "open":
            self = .open
        case "left":
            self = .left
        case "right":
            self = .right
        case "quit":
            self = .quit
        default:
            return nil
        }
    }
}

final class DisplayController {
    enum Move {
        case left
        case right
    }

    func perform(_ move: Move) {
        guard ensureAccessibility(prompt: true) else {
            NSSound.beep()
            return
        }

        guard let currentScreen = screenContaining(point: NSEvent.mouseLocation),
              let targetScreen = adjacentScreen(from: currentScreen, move: move)
        else {
            NSSound.beep()
            return
        }

        let frame = targetScreen.frame
        let insetX: CGFloat = min(max(frame.width * 0.03, 12), 80)
        let point = CGPoint(
            x: move == .left ? frame.maxX - insetX : frame.minX + insetX,
            y: frame.midY
        )

        let source = CGEventSource(stateID: .hidSystemState)
        CGWarpMouseCursorPosition(point)
        usleep(50_000)

        guard let moved = CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left),
              let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left),
              let up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)
        else {
            NSSound.beep()
            return
        }

        moved.post(tap: .cghidEventTap)
        usleep(20_000)
        down.post(tap: .cghidEventTap)
        usleep(20_000)
        up.post(tap: .cghidEventTap)
    }

    func ensureAccessibility(prompt: Bool) -> Bool {
        if prompt {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            return AXIsProcessTrustedWithOptions(options)
        }
        return AXIsProcessTrusted()
    }

    private func adjacentScreen(from currentScreen: NSScreen, move: Move) -> NSScreen? {
        let currentFrame = currentScreen.frame
        let candidates = NSScreen.screens.filter { $0 != currentScreen }

        switch move {
        case .left:
            return candidates
                .filter { $0.frame.midX < currentFrame.midX }
                .min { lhs, rhs in
                    abs(lhs.frame.midX - currentFrame.midX) < abs(rhs.frame.midX - currentFrame.midX)
                }
        case .right:
            return candidates
                .filter { $0.frame.midX > currentFrame.midX }
                .min { lhs, rhs in
                    abs(lhs.frame.midX - currentFrame.midX) < abs(rhs.frame.midX - currentFrame.midX)
                }
        }
    }

    private func screenContaining(point: CGPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(point) }
    }
}

final class DisplayKeysApp: NSObject, NSApplicationDelegate {
    private let displayController = DisplayController()
    private var statusItem: NSStatusItem?
    private var observers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        registerObservers()
        _ = displayController.ensureAccessibility(prompt: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        for observer in observers {
            DistributedNotificationCenter.default().removeObserver(observer)
        }
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "DS"

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Move Left Display", action: #selector(moveLeft), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Move Right Display", action: #selector(moveRight), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Open Accessibility Settings", action: #selector(openAccessibilitySettings), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))

        item.menu = menu
        statusItem = item
    }

    private func registerObservers() {
        let center = DistributedNotificationCenter.default()
        observers.append(center.addObserver(forName: .displayKeysMoveLeft, object: bundleIdentifier, queue: .main) { [weak self] _ in
            self?.displayController.perform(.left)
        })
        observers.append(center.addObserver(forName: .displayKeysMoveRight, object: bundleIdentifier, queue: .main) { [weak self] _ in
            self?.displayController.perform(.right)
        })
        observers.append(center.addObserver(forName: .displayKeysQuit, object: bundleIdentifier, queue: .main) { _ in
            NSApp.terminate(nil)
        })
    }

    @objc private func moveLeft() {
        displayController.perform(.left)
    }

    @objc private func moveRight() {
        displayController.perform(.right)
    }

    @objc private func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    static func postDistributedCommand(_ name: Notification.Name) {
        DistributedNotificationCenter.default().post(name: name, object: bundleIdentifier)
    }
}

guard let mode = Mode(argument: CommandLine.arguments.dropFirst().first) else {
    fputs("usage: DisplayKeys [open|left|right|quit]\n", stderr)
    exit(2)
}

switch mode {
case .open:
    let app = NSApplication.shared
    let delegate = DisplayKeysApp()
    app.delegate = delegate
    withExtendedLifetime(delegate) {
        app.run()
    }
case .left:
    DisplayController().perform(.left)
case .right:
    DisplayController().perform(.right)
case .quit:
    DisplayKeysApp.postDistributedCommand(.displayKeysQuit)
}
