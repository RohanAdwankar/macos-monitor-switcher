import AppKit
import Carbon

private let bundleIdentifier = "local.displaykeys"
private let logFile = "/tmp/displaykeys.log"

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
            log("move=\(move) failed=accessibility")
            NSSound.beep()
            return
        }

        let currentLocation = CGEvent(source: nil)?.location ?? .zero
        log("move=\(move) start currentLocation=\(currentLocation)")

        guard let targetScreen = targetScreen(for: move),
              let targetDisplayID = displayID(for: targetScreen)
        else {
            let screens = NSScreen.screens.compactMap { screen -> String? in
                guard let id = displayID(for: screen) else { return nil }
                return "id=\(id) bounds=\(CGDisplayBounds(id))"
            }.joined(separator: " | ")
            log("move=\(move) failed=screen-selection currentLocation=\(currentLocation) screens=\(screens)")
            NSSound.beep()
            return
        }

        let targetBounds = CGDisplayBounds(targetDisplayID)
        let inset: CGFloat = 10
        let entryPoint = CGPoint(
            x: move == .left ? inset : targetBounds.width - inset,
            y: inset
        )
        let safePoint = CGPoint(
            x: move == .left ? min(targetBounds.width * 0.35, targetBounds.width - 40) : max(targetBounds.width * 0.65, 40),
            y: min(targetBounds.height * 0.75, targetBounds.height - 80)
        )

        let source = CGEventSource(stateID: .hidSystemState)
        CGDisplayMoveCursorToPoint(targetDisplayID, entryPoint)
        usleep(35_000)
        CGDisplayMoveCursorToPoint(targetDisplayID, safePoint)
        usleep(35_000)

        let clickPoint = CGEvent(source: nil)?.location ?? currentLocation
        log("move=\(move) current=\(currentLocation) targetBounds=\(targetBounds) entryPoint=\(entryPoint) safePoint=\(safePoint) click=\(clickPoint)")

        guard let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: clickPoint, mouseButton: .left),
              let up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: clickPoint, mouseButton: .left)
        else {
            log("move=\(move) failed=event-creation click=\(clickPoint)")
            NSSound.beep()
            return
        }

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

    private func screenContaining(point: CGPoint) -> NSScreen? {
        NSScreen.screens.first { screen in
            guard let id = displayID(for: screen) else { return false }
            return CGDisplayBounds(id).contains(point)
        }
    }

    private func targetScreen(for move: Move) -> NSScreen? {
        let screens = NSScreen.screens.sorted { lhs, rhs in
            lhs.frame.midX < rhs.frame.midX
        }
        guard !screens.isEmpty else { return nil }
        return move == .left ? screens.first : screens.last
    }

    private func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        return CGDirectDisplayID(screenNumber.uint32Value)
    }

    private func log(_ message: String) {
        let line = "\(Date()) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }

        if FileManager.default.fileExists(atPath: logFile),
           let handle = FileHandle(forWritingAtPath: logFile) {
            try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
            try? handle.close()
        } else {
            FileManager.default.createFile(atPath: logFile, contents: data)
        }
    }
}

enum ShortcutAction: UInt32 {
    case left = 1
    case right = 2
}

struct ShortcutDefinition {
    let action: ShortcutAction
    let keyCode: UInt32
    let modifiers: UInt32
}

final class HotKeyCenter {
    static let shared = HotKeyCenter()

    private let signature: OSType = 0x4453504B // DSPK
    private var handlers: [UInt32: () -> Void] = [:]
    private var registeredHotKeys: [EventHotKeyRef?] = []
    private var eventHandler: EventHandlerRef?

    func register(_ shortcut: ShortcutDefinition, handler: @escaping () -> Void) {
        installHandlerIfNeeded()

        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: signature, id: shortcut.action.rawValue)
        let status = RegisterEventHotKey(shortcut.keyCode,
                                         shortcut.modifiers,
                                         hotKeyID,
                                         GetEventDispatcherTarget(),
                                         0,
                                         &hotKeyRef)

        guard status == noErr else {
            NSLog("Failed to register hotkey \(shortcut.action) status=\(status)")
            return
        }

        handlers[shortcut.action.rawValue] = handler
        registeredHotKeys.append(hotKeyRef)
    }

    private func installHandlerIfNeeded() {
        guard eventHandler == nil else { return }

        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetEventDispatcherTarget(), { _, event, _ in
            guard let event else { return noErr }

            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(event,
                                           EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID),
                                           nil,
                                           MemoryLayout<EventHotKeyID>.size,
                                           nil,
                                           &hotKeyID)
            guard status == noErr else { return noErr }

            HotKeyCenter.shared.handlers[hotKeyID.id]?()
            return noErr
        }, 1, &eventSpec, nil, &eventHandler)
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
        registerHotKeys()
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

    private func registerHotKeys() {
        let shortcuts = [
            ShortcutDefinition(action: .left,
                               keyCode: UInt32(kVK_LeftArrow),
                               modifiers: UInt32(controlKey | shiftKey)),
            ShortcutDefinition(action: .right,
                               keyCode: UInt32(kVK_RightArrow),
                               modifiers: UInt32(controlKey | shiftKey))
        ]

        for shortcut in shortcuts {
            HotKeyCenter.shared.register(shortcut) { [weak self] in
                switch shortcut.action {
                case .left:
                    self?.displayController.perform(.left)
                case .right:
                    self?.displayController.perform(.right)
                }
            }
        }
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
