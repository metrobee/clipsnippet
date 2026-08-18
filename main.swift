import Cocoa
import Carbon
import Contacts

// Key codes
let kVK_ANSI_C: UInt32 = 0x08
let cmdKey = 0x0100
let optionKey = 0x0800
let kEventClassKeyboard = 0x6b657962 // 'keyb'
let kEventHotKeyPressed = 5 // Correct value from Carbon (was 1)

func logMessage(_ msg: String) {
    let logFile = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".clipsnippet_log.txt")
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    let line = "[\(formatter.string(from: Date()))] \(msg)\n"
    if let data = line.data(using: .utf8) {
        if FileManager.default.fileExists(atPath: logFile.path) {
            if let fileHandle = try? FileHandle(forWritingTo: logFile) {
                fileHandle.seekToEndOfFile()
                fileHandle.write(data)
                fileHandle.closeFile()
            }
        } else {
            try? data.write(to: logFile)
        }
    }
}
func hotKeyHandler(nextHandler: EventHandlerCallRef?, theEvent: EventRef?, userData: UnsafeMutableRawPointer?) -> OSStatus {
    logMessage("Hotkey handler triggered globally!")
    DispatchQueue.main.async {
        AppDelegate.shared?.toggleWindow()
    }
    return noErr
}

var typedBuffer = ""

func myEventTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let refcon = refcon {
            let appDelegate = Unmanaged<AppDelegate>.fromOpaque(refcon).takeUnretainedValue()
            if let tap = appDelegate.eventTapRef {
                CGEvent.tapEnable(tap: tap, enable: true)
                logMessage("Re-enabled event tap after timeout.")
            }
        }
        return Unmanaged.passUnretained(event)
    }
    
    if type == .keyDown {
        // If our app is currently active (search window open), bypass text expansion
        // so that typing inside ClipSnippet is not intercepted and doesn't pollute the trigger buffer.
        if NSApp.isActive {
            typedBuffer = ""
            return Unmanaged.passUnretained(event)
        }
        
        guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
        let appDelegate = Unmanaged<AppDelegate>.fromOpaque(refcon).takeUnretainedValue()
        
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        
        // backspace
        if keyCode == 51 {
            if !typedBuffer.isEmpty {
                typedBuffer.removeLast()
            }
            return Unmanaged.passUnretained(event)
        }
        
        if let nsEvent = NSEvent(cgEvent: event) {
            let flags = nsEvent.modifierFlags
            if flags.contains(.command) || flags.contains(.control) {
                typedBuffer = ""
                return Unmanaged.passUnretained(event)
            }
            
            if let chars = nsEvent.characters, !chars.isEmpty {
                let char = chars.first!
                
                // Reset buffer on Return (36), Tab (48), Escape (53)
                if keyCode == 36 || keyCode == 48 || keyCode == 53 {
                    typedBuffer = ""
                    return Unmanaged.passUnretained(event)
                }
                
                typedBuffer.append(char)
                if typedBuffer.count > 50 {
                    typedBuffer.removeFirst()
                }
                
                if let matchedTrigger = appDelegate.checkTriggers(buffer: typedBuffer) {
                    typedBuffer = ""
                    appDelegate.expandSnippet(trigger: matchedTrigger, deleteCount: matchedTrigger.count)
                    return nil
                }
            }
        }
    }
    return Unmanaged.passUnretained(event)
}

struct ClipItem: Codable {
    let text: String
    let isSnippet: Bool
    let trigger: String?
    let title: String
    let category: String?
    var systemCommandId: String? = nil // For system commands
    var filePath: String? = nil // For file & folder navigation
    var isDirectory: Bool = false // For folder navigation
}

struct ContactClipItem {
    let item: ClipItem
    let searchString: String
}

// MARK: - System Commands

enum SystemCommandCategory: String {
    case files = "Files & Storage"
    case power = "Power & Session"
    case display = "Display & Appearance"
    case audio = "Audio"
    case apps = "Apps"
}

struct SystemCommand {
    let id: String
    let name: String
    let icon: String
    let category: SystemCommandCategory
    let keywords: [String]
    let requiresConfirmation: Bool
    let execute: () -> Void
    
    var searchableText: String {
        return "\(name) \(keywords.joined(separator: " ")) \(category.rawValue)".lowercased()
    }
}

class SystemCommands {
    static let shared = SystemCommands()
    var allCommands: [SystemCommand] = []
    
    private init() {
        setupCommands()
    }
    
    private func setupCommands() {
        allCommands = [
            // Files & Storage
            SystemCommand(
                id: "empty_trash",
                name: "Empty Trash",
                icon: "🗑️",
                category: .files,
                keywords: ["delete", "remove", "clean", "clear", "prügikast", "tühjenda"],
                requiresConfirmation: false,
                execute: { self.emptyTrash() }
            ),
            SystemCommand(
                id: "open_trash",
                name: "Open Trash",
                icon: "🗑️",
                category: .files,
                keywords: ["show", "view", "prügikast", "ava"],
                requiresConfirmation: false,
                execute: { self.openTrash() }
            ),
            SystemCommand(
                id: "toggle_hidden_files",
                name: "Toggle Hidden Files",
                icon: "👁️",
                category: .files,
                keywords: ["show", "hide", "invisible", "dot", "peidetud", "failid"],
                requiresConfirmation: false,
                execute: { self.toggleHiddenFiles() }
            ),
            SystemCommand(
                id: "eject_disks",
                name: "Eject All Disks",
                icon: "💾",
                category: .files,
                keywords: ["unmount", "remove", "usb", "väljasta", "kettad"],
                requiresConfirmation: false,
                execute: { self.ejectAllDisks() }
            ),
            
            // Power & Session
            SystemCommand(
                id: "lock_screen",
                name: "Lock Screen",
                icon: "🔒",
                category: .power,
                keywords: ["secure", "away", "lukusta", "ekraan"],
                requiresConfirmation: false,
                execute: { self.lockScreen() }
            ),
            SystemCommand(
                id: "sleep",
                name: "Sleep",
                icon: "💤",
                category: .power,
                keywords: ["suspend", "hibernate", "uni", "puhkerežiim"],
                requiresConfirmation: false,
                execute: { self.sleep() }
            ),
            SystemCommand(
                id: "restart",
                name: "Restart",
                icon: "🔄",
                category: .power,
                keywords: ["reboot", "taaskäivita"],
                requiresConfirmation: true,
                execute: { self.restart() }
            ),
            SystemCommand(
                id: "shutdown",
                name: "Shut Down",
                icon: "⏻",
                category: .power,
                keywords: ["power off", "turn off", "sulge", "lülita välja"],
                requiresConfirmation: true,
                execute: { self.shutdown() }
            ),
            SystemCommand(
                id: "logout",
                name: "Log Out",
                icon: "👤",
                category: .power,
                keywords: ["sign out", "exit", "logi välja"],
                requiresConfirmation: true,
                execute: { self.logout() }
            ),
            
            // Display & Appearance
            SystemCommand(
                id: "show_desktop",
                name: "Show Desktop",
                icon: "🖥️",
                category: .display,
                keywords: ["minimize", "hide windows", "näita", "töölaud"],
                requiresConfirmation: false,
                execute: { self.showDesktop() }
            ),
            SystemCommand(
                id: "toggle_dark_mode",
                name: "Toggle Dark Mode",
                icon: "🌙",
                category: .display,
                keywords: ["theme", "appearance", "light", "dark", "tume", "hele"],
                requiresConfirmation: false,
                execute: { self.toggleDarkMode() }
            ),
            
            // Audio
            SystemCommand(
                id: "toggle_mute",
                name: "Toggle Mute",
                icon: "🔇",
                category: .audio,
                keywords: ["sound", "volume", "silent", "vaigista", "heli"],
                requiresConfirmation: false,
                execute: { self.toggleMute() }
            ),
            SystemCommand(
                id: "volume_up",
                name: "Volume Up",
                icon: "🔊",
                category: .audio,
                keywords: ["sound", "louder", "increase", "valjemaks", "heli"],
                requiresConfirmation: false,
                execute: { self.volumeUp() }
            ),
            SystemCommand(
                id: "volume_down",
                name: "Volume Down",
                icon: "🔉",
                category: .audio,
                keywords: ["sound", "quieter", "decrease", "vaiksemaks", "heli"],
                requiresConfirmation: false,
                execute: { self.volumeDown() }
            ),
            
            // Apps
            SystemCommand(
                id: "hide_all_apps",
                name: "Hide All Apps",
                icon: "📦",
                category: .apps,
                keywords: ["minimize", "clear", "peida", "rakendused"],
                requiresConfirmation: false,
                execute: { self.hideAllApps() }
            ),
            SystemCommand(
                id: "quit_all_apps",
                name: "Quit All Apps",
                icon: "❌",
                category: .apps,
                keywords: ["close", "exit", "sulge", "rakendused"],
                requiresConfirmation: true,
                execute: { self.quitAllApps() }
            ),
            SystemCommand(
                id: "dismiss_notifications",
                name: "Dismiss Notifications",
                icon: "🔕",
                category: .apps,
                keywords: ["clear", "close", "teated", "sulge"],
                requiresConfirmation: false,
                execute: { self.dismissNotifications() }
            )
        ]
    }
    
    // MARK: - Helper Methods
    
    @discardableResult
    func runAppleScript(_ script: String) -> Bool {
        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            appleScript.executeAndReturnError(&error)
            if error == nil {
                return true
            }
            logMessage("NSAppleScript execution note: \(String(describing: error)), falling back to osascript process...")
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let pipe = Pipe()
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                logMessage("osascript process execution succeeded")
                return true
            } else {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let errStr = String(data: data, encoding: .utf8) ?? ""
                logMessage("osascript process failed with code \(process.terminationStatus): \(errStr.trimmingCharacters(in: .whitespacesAndNewlines))")
                return false
            }
        } catch {
            logMessage("Failed to spawn osascript process: \(error.localizedDescription)")
            return false
        }
    }
    
    // MARK: - Files & Storage Actions
    
    private func emptyTrash() {
        logMessage("SystemCommand: Empty Trash")
        DispatchQueue.global(qos: .userInitiated).async {
            // 1. Tell Finder to empty trash (standard macOS way)
            let finderScript = """
            tell application "Finder"
                empty trash
            end tell
            """
            let success = self.runAppleScript(finderScript)
            
            // 2. Also remove file locks and delete directly via shell process
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-c", "chflags -R nouchg ~/.Trash/* ~/.Trash/.* 2>/dev/null; rm -rf ~/.Trash/* ~/.Trash/.* 2>/dev/null"]
            try? process.run()
            process.waitUntilExit()
            
            DispatchQueue.main.async {
                NSSound(named: "Purr")?.play()
            }
            logMessage("Empty Trash completed (Finder AppleScript success: \(success))")
        }
    }
    
    private func openTrash() {
        logMessage("SystemCommand: Open Trash")
        let script = """
        tell application "Finder"
            open trash
            activate
        end tell
        """
        if !self.runAppleScript(script) {
            let trashURL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".Trash")
            NSWorkspace.shared.open(trashURL)
        }
    }
    
    private func toggleHiddenFiles() {
        logMessage("SystemCommand: Toggle Hidden Files")
        let script = """
        set currentState to do shell script "defaults read com.apple.finder AppleShowAllFiles"
        if currentState is "1" or currentState is "TRUE" or currentState is "YES" then
            do shell script "defaults write com.apple.finder AppleShowAllFiles -bool false"
        else
            do shell script "defaults write com.apple.finder AppleShowAllFiles -bool true"
        end if
        tell application "Finder"
            quit
            delay 0.1
            activate
        end tell
        """
        if !self.runAppleScript(script) {
            // Shell fallback
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-c", "if [ \"$(defaults read com.apple.finder AppleShowAllFiles 2>/dev/null)\" = \"true\" ]; then defaults write com.apple.finder AppleShowAllFiles -bool false; else defaults write com.apple.finder AppleShowAllFiles -bool true; fi; killall Finder"]
            try? process.run()
        }
    }
    
    private func ejectAllDisks() {
        logMessage("SystemCommand: Eject All Disks")
        let script = """
        tell application "Finder"
            eject (every disk whose ejectable is true)
        end tell
        """
        self.runAppleScript(script)
    }
    
    // MARK: - Power & Session Actions
    
    private func lockScreen() {
        logMessage("SystemCommand: Lock Screen")
        let script = """
        tell application "System Events"
            keystroke "q" using {control down, command down}
        end tell
        """
        if !self.runAppleScript(script) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
            process.arguments = ["displaysleepnow"]
            try? process.run()
        }
    }
    
    private func sleep() {
        logMessage("SystemCommand: Sleep")
        let script = """
        tell application "System Events"
            sleep
        end tell
        """
        if !self.runAppleScript(script) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
            process.arguments = ["sleepnow"]
            try? process.run()
        }
    }
    
    private func restart() {
        logMessage("SystemCommand: Restart")
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Restart Computer?"
            alert.informativeText = "Are you sure you want to restart your computer? All unsaved changes will be lost."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Restart")
            alert.addButton(withTitle: "Cancel")
            
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                let script = """
                tell application "System Events"
                    restart
                end tell
                """
                self.runAppleScript(script)
            }
        }
    }
    
    private func shutdown() {
        logMessage("SystemCommand: Shut Down")
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Shut Down Computer?"
            alert.informativeText = "Are you sure you want to shut down your computer? All unsaved changes will be lost."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Shut Down")
            alert.addButton(withTitle: "Cancel")
            
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                let script = """
                tell application "System Events"
                    shut down
                end tell
                """
                self.runAppleScript(script)
            }
        }
    }
    
    private func logout() {
        logMessage("SystemCommand: Log Out")
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Log Out?"
            alert.informativeText = "Are you sure you want to log out? All unsaved changes will be lost."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Log Out")
            alert.addButton(withTitle: "Cancel")
            
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                let script = """
                tell application "System Events"
                    log out
                end tell
                """
                self.runAppleScript(script)
            }
        }
    }
    
    // MARK: - Display & Appearance Actions
    
    private func showDesktop() {
        logMessage("SystemCommand: Show Desktop")
        let script = """
        tell application "System Events"
            key code 103 using {command down, function down}
        end tell
        """
        self.runAppleScript(script)
    }
    
    private func toggleDarkMode() {
        logMessage("SystemCommand: Toggle Dark Mode")
        let script = """
        tell application "System Events"
            tell appearance preferences
                set dark mode to not dark mode
            end tell
        end tell
        """
        self.runAppleScript(script)
    }
    
    // MARK: - Audio Actions
    
    private func toggleMute() {
        logMessage("SystemCommand: Toggle Mute")
        let script = """
        set currentVolume to output volume of (get volume settings)
        if output muted of (get volume settings) then
            set volume output muted false
        else
            set volume output muted true
        end if
        """
        self.runAppleScript(script)
    }
    
    private func volumeUp() {
        logMessage("SystemCommand: Volume Up")
        let script = """
        set currentVolume to output volume of (get volume settings)
        if currentVolume < 100 then
            set volume output volume (currentVolume + 10)
        end if
        """
        self.runAppleScript(script)
    }
    
    private func volumeDown() {
        logMessage("SystemCommand: Volume Down")
        let script = """
        set currentVolume to output volume of (get volume settings)
        if currentVolume > 0 then
            set volume output volume (currentVolume - 10)
        end if
        """
        self.runAppleScript(script)
    }
    
    // MARK: - Apps Actions
    
    private func hideAllApps() {
        logMessage("SystemCommand: Hide All Apps")
        let script = """
        tell application "System Events"
            set visible of every process whose visible is true and name is not "Finder" to false
        end tell
        """
        self.runAppleScript(script)
    }
    
    private func quitAllApps() {
        logMessage("SystemCommand: Quit All Apps")
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Quit All Applications?"
            alert.informativeText = "Are you sure you want to quit all running applications? Unsaved work may be lost."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Quit All")
            alert.addButton(withTitle: "Cancel")
            
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                let excludedApps = ["Finder", "ClipSnippet"]
                let runningApps = NSWorkspace.shared.runningApplications
                
                for app in runningApps {
                    if let appName = app.localizedName,
                       !excludedApps.contains(appName),
                       app.activationPolicy == .regular {
                        app.terminate()
                    }
                }
                logMessage("Quit All Apps completed")
            }
        }
    }
    
    private func dismissNotifications() {
        logMessage("SystemCommand: Dismiss Notifications")
        let script = """
        tell application "System Events"
            tell process "NotificationCenter"
                try
                    click button 1 of every window
                end try
            end tell
        end tell
        """
        self.runAppleScript(script)
    }
}

class BorderlessWindow: NSPanel {
    override var canBecomeKey: Bool {
        return true
    }
    
    override var canBecomeMain: Bool {
        return true
    }
    
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command) {
            if let characters = event.charactersIgnoringModifiers,
               let num = Int(characters), num >= 1 && num <= 9 {
                if let appDelegate = NSApp.delegate as? AppDelegate {
                    appDelegate.selectAndPasteShortcut(number: num)
                    return true
                }
            }
        }
        
        // Delete history items using Option+Delete, Control+Delete, Command+Delete
        // or just Backspace/Delete if the search field is empty
        if event.keyCode == 51 || event.keyCode == 117 {
            let hasOption = event.modifierFlags.contains(.option)
            let hasControl = event.modifierFlags.contains(.control)
            let hasCommand = event.modifierFlags.contains(.command)
            
            if let appDelegate = NSApp.delegate as? AppDelegate {
                let isEmpty = appDelegate.searchField?.stringValue.isEmpty ?? true
                if hasOption || hasControl || hasCommand || (event.keyCode == 51 && isEmpty) || event.keyCode == 117 {
                    appDelegate.deleteSelectedHistoryItem()
                    return true
                }
            }
        }
        
        return super.performKeyEquivalent(with: event)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate {
    static var shared: AppDelegate?
    
    var window: BorderlessWindow!
    var visualEffectView: NSVisualEffectView!
    var searchField: NSTextField!
    var tableView: NSTableView!
    var scrollView: NSScrollView!
    var statusItem: NSStatusItem!
    
    var hotKeyRef1: EventHotKeyRef?
    var hotKeyRef2: EventHotKeyRef?
    var hotKeyRef3: EventHotKeyRef?
    var eventHandlerRef: EventHandlerRef?
    var lastChangeCount = 0
    var clipboardHistory: [String] = []
    var customSnippets: [String: [String: String]] = [:]
    var fileMonitorSource: DispatchSourceFileSystemObject?
    var allContactsCache: [ContactClipItem] = []
    var eventTapRef: CFMachPort?
    var eventTapSource: CFRunLoopSource?
    
    enum TableRow {
        case header(title: String)
        case item(ClipItem)
    }
    
    var filteredRows: [TableRow] = []
    
    let historyFile = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".clipsnippet_history.json")
    let snippetsFile = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".clipsnippet_snippets.json")
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        
        // Load data
        loadSnippets()
        loadHistory()
        startMonitoringSnippetsFile()
        
        // Request Contacts Access
        let contactStore = CNContactStore()
        let contactStatus = CNContactStore.authorizationStatus(for: .contacts)
        if contactStatus == .notDetermined {
            logMessage("Requesting Contacts access...")
            contactStore.requestAccess(for: .contacts) { [weak self] granted, error in
                if granted {
                    logMessage("Contacts access granted.")
                    self?.loadContactsCache()
                } else {
                    logMessage("Contacts access denied: \(String(describing: error))")
                }
            }
        } else if contactStatus == .authorized {
            loadContactsCache()
        }
        
        // Set up status bar
        setupStatusItem()
        
        // Build window
        setupWindow()
        
        // Update items
        updateAllItems()
        
        // Register global shortcut (Cmd + Option + C)
        registerHotKey()
        
        // Setup global event tap for text expansion
        setupEventTap()
        
        // Start clipboard monitoring timer (every 0.5 seconds)
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkClipboard()
        }
        
        logMessage("ClipSnippet running in background. Global hotkeys registered.")
    }
    
    func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.title = "📋"
            button.toolTip = "ClipSnippet"
        }
        
        let menu = NSMenu()
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.2.0"
        let versionItem = NSMenuItem(title: "ClipSnippet v\(version)", action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        menu.addItem(versionItem)
        menu.addItem(NSMenuItem.separator())
        
        menu.addItem(NSMenuItem(title: "Show Clipboard (⌥⌘C)", action: #selector(toggleWindow), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Edit Snippets...", action: #selector(editSnippetsFile), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Clear History", action: #selector(clearHistory), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    
    func setupWindow() {
        let width: CGFloat = 600
        let height: CGFloat = 400
        
        let screenRect = NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let rect = CGRect(
            x: (screenRect.width - width) / 2,
            y: (screenRect.height - height) / 2 + 100,
            width: width,
            height: height
        )
        
        window = BorderlessWindow(
            contentRect: rect,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .statusBar
        window.delegate = self
        
        // Glassmorphic background blur
        visualEffectView = NSVisualEffectView(frame: CGRect(x: 0, y: 0, width: width, height: height))
        visualEffectView.material = .hudWindow
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .active
        visualEffectView.wantsLayer = true
        visualEffectView.layer?.cornerRadius = 14
        visualEffectView.layer?.masksToBounds = true
        window.contentView = visualEffectView
        
        // Search text field
        searchField = NSTextField()
        searchField.isBezeled = false
        searchField.drawsBackground = false
        searchField.focusRingType = .none
        searchField.font = NSFont.systemFont(ofSize: 18)
        searchField.placeholderString = "Type to search history, snippets & contacts..."
        searchField.delegate = self
        
        // Table view scroll view
        scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        
        // Table view setup
        tableView = NSTableView()
        tableView.headerView = nil
        tableView.backgroundColor = .clear
        tableView.rowHeight = 32
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(tableDoubleClicked)
        
        let col1 = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("text"))
        col1.width = width - 130
        col1.resizingMask = [.autoresizingMask]
        tableView.addTableColumn(col1)
        
        let col2 = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("shortcut"))
        col2.width = 60
        col2.resizingMask = []
        if let cell = col2.dataCell as? NSCell {
            cell.alignment = .center
        }
        tableView.addTableColumn(col2)
        
        scrollView.documentView = tableView
        
        // Layout using Auto Layout
        searchField.translatesAutoresizingMaskIntoConstraints = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        
        visualEffectView.addSubview(searchField)
        visualEffectView.addSubview(scrollView)
        
        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: visualEffectView.topAnchor, constant: 16),
            searchField.leadingAnchor.constraint(equalTo: visualEffectView.leadingAnchor, constant: 16),
            searchField.trailingAnchor.constraint(equalTo: visualEffectView.trailingAnchor, constant: -16),
            searchField.heightAnchor.constraint(equalToConstant: 28),
            
            scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: visualEffectView.leadingAnchor, constant: 16),
            scrollView.trailingAnchor.constraint(equalTo: visualEffectView.trailingAnchor, constant: -16),
            scrollView.bottomAnchor.constraint(equalTo: visualEffectView.bottomAnchor, constant: -16)
        ])
    }
    
    func registerHotKey() {
        var eventType = EventTypeSpec()
        eventType.eventClass = UInt32(kEventClassKeyboard)
        eventType.eventKind = UInt32(kEventHotKeyPressed)
        
        let handlerStatus = InstallEventHandler(GetApplicationEventTarget(), hotKeyHandler, 1, &eventType, nil, &self.eventHandlerRef)
        logMessage("InstallEventHandler status: \(handlerStatus)")
        
        let signature = UInt32(1129525297) // 'CS01'
        
        // 1. Option + Command + C
        var hotKeyID1 = EventHotKeyID()
        hotKeyID1.signature = signature
        hotKeyID1.id = UInt32(1)
        let modifiers1 = UInt32(cmdKey | optionKey)
        let status1 = RegisterEventHotKey(kVK_ANSI_C, modifiers1, hotKeyID1, GetApplicationEventTarget(), 0, &self.hotKeyRef1)
        logMessage("Register Cmd+Option+C status: \(status1)")
        
        // 2. Control + Option + C
        var hotKeyID2 = EventHotKeyID()
        hotKeyID2.signature = signature
        hotKeyID2.id = UInt32(2)
        let controlKeyVal = 0x1000 // 4096 in Carbon
        let modifiers2 = UInt32(controlKeyVal | optionKey)
        let status2 = RegisterEventHotKey(kVK_ANSI_C, modifiers2, hotKeyID2, GetApplicationEventTarget(), 0, &self.hotKeyRef2)
        logMessage("Register Control+Option+C status: \(status2)")
        
        // 3. Control + Option + Space (Space is keycode 49)
        var hotKeyID3 = EventHotKeyID()
        hotKeyID3.signature = signature
        hotKeyID3.id = UInt32(3)
        let status3 = RegisterEventHotKey(49, modifiers2, hotKeyID3, GetApplicationEventTarget(), 0, &self.hotKeyRef3)
        logMessage("Register Control+Option+Space status: \(status3)")
    }
    
    func setupEventTap(promptUser: Bool = true) {
        if promptUser {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }
        let isTrusted = AXIsProcessTrusted()
        logMessage("Accessibility trusted status: \(isTrusted)")
        
        let eventMask = (1 << CGEventType.keyDown.rawValue)
        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: myEventTapCallback,
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        ) else {
            // Silently retry every 3 seconds without popup modals
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                if self?.eventTapRef == nil {
                    self?.setupEventTap(promptUser: false)
                }
            }
            return
        }
        
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        self.eventTapRef = eventTap
        self.eventTapSource = runLoopSource
        logMessage("Global event tap (text expansion) set up successfully.")
    }
    
    @objc func toggleWindow() {
        if window.isVisible {
            hideWindow()
        } else {
            showWindow()
        }
    }
    
    func showWindow() {
        // Center window on screen where cursor is
        if let mouseLocation = NSScreen.main?.frame {
            let width = window.frame.width
            let height = window.frame.height
            window.setFrame(CGRect(
                x: (mouseLocation.width - width) / 2,
                y: (mouseLocation.height - height) / 2 + 100,
                width: width,
                height: height
            ), display: true)
        }
        
        loadSnippets()
        loadContactsCache()
        updateAllItems()
        searchField.stringValue = ""
        filterItems(query: "")
        
        // Order front regardless to bypass any window level or accessory activation restrictions
        window.orderFrontRegardless()
        
        // Modern application activation
        NSApp.activate(ignoringOtherApps: true)
        NSRunningApplication.current.activate(options: [.activateAllWindows])
        
        // Make window key and front
        window.makeKeyAndOrderFront(nil)
        
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            NSRunningApplication.current.activate(options: [.activateAllWindows])
            self.window.orderFrontRegardless()
            self.window.makeKeyAndOrderFront(nil)
            self.window.makeFirstResponder(self.searchField)
        }
    }
    
    func hideWindow() {
        window.orderOut(nil)
        NSApp.hide(nil)
    }
    
    func windowDidResignKey(_ notification: Notification) {
        hideWindow()
    }
    
    // ----------------------------------------------------
    // Clipboard Logic
    // ----------------------------------------------------
    func checkClipboard() {
        let pasteboard = NSPasteboard.general
        if pasteboard.changeCount != lastChangeCount {
            lastChangeCount = pasteboard.changeCount
            if let str = pasteboard.string(forType: .string) {
                let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    addHistoryItem(trimmed)
                }
            }
        }
    }
    
    func addHistoryItem(_ text: String) {
        // Avoid duplicate consecutive items
        if let first = clipboardHistory.first, first == text {
            return
        }
        
        // Remove existing to move to top
        if let idx = clipboardHistory.firstIndex(of: text) {
            clipboardHistory.remove(at: idx)
        }
        
        clipboardHistory.insert(text, at: 0)
        
        // Limit history to 100 items
        if clipboardHistory.count > 100 {
            clipboardHistory.removeLast()
        }
        
        saveHistory()
        updateAllItems()
    }
    
    func loadHistory() {
        if let data = try? Data(contentsOf: historyFile),
           let list = try? JSONDecoder().decode([String].self, from: data) {
            clipboardHistory = list
        }
    }
    
    func saveHistory() {
        if let data = try? JSONEncoder().encode(clipboardHistory) {
            try? data.write(to: historyFile)
        }
    }
    
    func loadSnippets() {
        if !FileManager.default.fileExists(atPath: snippetsFile.path) {
            // Write default snippets
            let defaults: [String: [String: String]] = [
                "Üldised": [
                    ":date": "Current Date",
                    ":time": "Current Time",
                    ":shrug": "¯\\_(ツ)_/¯",
                    ":br": "Best regards,\nMetrobee",
                    ":koor": "Segakoor Hilaro"
                ]
            ]
            if let data = try? JSONEncoder().encode(defaults) {
                try? data.write(to: snippetsFile)
            }
            customSnippets = defaults
        } else {
            if let data = try? Data(contentsOf: snippetsFile) {
                if let map = try? JSONDecoder().decode([String: [String: String]].self, from: data) {
                    customSnippets = map
                } else if let flatMap = try? JSONDecoder().decode([String: String].self, from: data) {
                    customSnippets = ["Üldised": flatMap]
                }
            }
        }
    }
    
    func startMonitoringSnippetsFile() {
        let fileDescriptor = open(snippetsFile.path, O_EVTONLY)
        guard fileDescriptor >= 0 else { return }
        
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .delete, .rename],
            queue: DispatchQueue.main
        )
        
        source.setEventHandler { [weak self] in
            guard let self = self else { return }
            logMessage("Snippets file change detected, reloading...")
            
            let flags = source.data
            if flags.contains(.delete) || flags.contains(.rename) {
                self.fileMonitorSource?.cancel()
                self.fileMonitorSource = nil
                close(fileDescriptor)
                
                // Wait 0.1s for the file replacement to complete, then monitor again and reload
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.startMonitoringSnippetsFile()
                    self.loadSnippets()
                    self.updateAllItems()
                }
            } else {
                self.loadSnippets()
                self.updateAllItems()
            }
        }
        
        source.setCancelHandler {
            close(fileDescriptor)
        }
        
        self.fileMonitorSource = source
        source.resume()
    }
    
    func updateAllItems() {
        if let sf = searchField {
            filterItems(query: sf.stringValue)
        } else {
            filterItems(query: "")
        }
    }
    
    func fetchFileSystemItems(query: String) -> [TableRow] {
        var rawPath = query
        if rawPath.hasPrefix("~") {
            rawPath = NSHomeDirectory() + rawPath.dropFirst()
        }
        
        var targetDir = rawPath
        var filterPrefix = ""
        
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: rawPath, isDirectory: &isDir) {
            if !isDir.boolValue {
                // Exact file match
                let fileName = URL(fileURLWithPath: rawPath).lastPathComponent
                return [
                    .header(title: "📄 Fail"),
                    .item(ClipItem(
                        text: rawPath,
                        isSnippet: false,
                        trigger: nil,
                        title: "📄 \(fileName)",
                        category: "Files",
                        systemCommandId: nil,
                        filePath: rawPath,
                        isDirectory: false
                    ))
                ]
            } else {
                targetDir = rawPath
                filterPrefix = ""
            }
        } else {
            let url = URL(fileURLWithPath: rawPath)
            targetDir = url.deletingLastPathComponent().path
            filterPrefix = url.lastPathComponent.lowercased()
        }
        
        guard FileManager.default.fileExists(atPath: targetDir) else { return [] }
        
        do {
            let contents = try FileManager.default.contentsOfDirectory(atPath: targetDir)
            let filtered = contents.filter { name in
                if name.hasPrefix(".") && !filterPrefix.hasPrefix(".") { return false }
                if filterPrefix.isEmpty { return true }
                return name.lowercased().contains(filterPrefix)
            }.sorted { (a, b) -> Bool in
                let aPath = (targetDir as NSString).appendingPathComponent(a)
                let bPath = (targetDir as NSString).appendingPathComponent(b)
                var aIsDir: ObjCBool = false
                var bIsDir: ObjCBool = false
                FileManager.default.fileExists(atPath: aPath, isDirectory: &aIsDir)
                FileManager.default.fileExists(atPath: bPath, isDirectory: &bIsDir)
                if aIsDir.boolValue != bIsDir.boolValue {
                    return aIsDir.boolValue
                }
                return a.localizedCaseInsensitiveCompare(b) == .orderedAscending
            }
            
            var rows: [TableRow] = []
            let displayDir = targetDir.replacingOccurrences(of: NSHomeDirectory(), with: "~")
            rows.append(.header(title: "📁 Kaust: \(displayDir)"))
            
            for name in filtered.prefix(50) {
                let itemPath = (targetDir as NSString).appendingPathComponent(name)
                var isItemDir: ObjCBool = false
                FileManager.default.fileExists(atPath: itemPath, isDirectory: &isItemDir)
                
                let icon = isItemDir.boolValue ? "📁" : "📄"
                let title = "\(icon) \(name)"
                
                rows.append(.item(ClipItem(
                    text: itemPath,
                    isSnippet: false,
                    trigger: nil,
                    title: title,
                    category: "Files",
                    systemCommandId: nil,
                    filePath: itemPath,
                    isDirectory: isItemDir.boolValue
                )))
            }
            return rows
        } catch {
            return []
        }
    }
    
    func filterItems(query: String) {
        var newRows: [TableRow] = []
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        
        // 1. File & Folder Navigation Mode (starts with ~ or /)
        if trimmed.hasPrefix("~") || trimmed.hasPrefix("/") {
            let fsRows = fetchFileSystemItems(query: trimmed)
            if !fsRows.isEmpty {
                filteredRows = fsRows
                tableView.reloadData()
                if let firstSelectable = filteredRows.firstIndex(where: {
                    if case .item = $0 { return true }
                    return false
                }) {
                    tableView.selectRowIndexes(IndexSet(integer: firstSelectable), byExtendingSelection: false)
                    tableView.scrollRowToVisible(firstSelectable)
                }
                return
            }
        }
        
        // 2. Process System Commands (ONLY when user explicitly types a keyword, NOT when empty!)
        if !trimmed.isEmpty {
            let matchingCommands = SystemCommands.shared.allCommands.filter { command in
                command.searchableText.contains(trimmed.lowercased())
            }
            
            if !matchingCommands.isEmpty {
                newRows.append(.header(title: "⚡️ Süsteemikäsud (System Actions)"))
                for command in matchingCommands {
                    let item = ClipItem(
                        text: command.name,
                        isSnippet: false,
                        trigger: nil,
                        title: "\(command.icon) \(command.name)",
                        category: "System",
                        systemCommandId: command.id,
                        filePath: nil,
                        isDirectory: false
                    )
                    newRows.append(.item(item))
                }
            }
        }
        
        // 3. Process clipboard history (ALWAYS AT THE TOP when query is empty!)
        let matchingHistory: [ClipItem]
        if trimmed.isEmpty {
            matchingHistory = clipboardHistory.map { ClipItem(text: $0, isSnippet: false, trigger: nil, title: $0, category: nil, systemCommandId: nil, filePath: nil, isDirectory: false) }
        } else {
            matchingHistory = clipboardHistory
                .filter { $0.localizedCaseInsensitiveContains(trimmed) }
                .map { ClipItem(text: $0, isSnippet: false, trigger: nil, title: $0, category: nil, systemCommandId: nil, filePath: nil, isDirectory: false) }
        }
        
        if !matchingHistory.isEmpty {
            newRows.append(.header(title: "📋 Clipboard History"))
            for item in matchingHistory {
                newRows.append(.item(item))
            }
        }
        
        // 4. Process custom snippets by category
        let sortedCategories = customSnippets.keys.sorted()
        for category in sortedCategories {
            if let snippets = customSnippets[category] {
                let sortedTriggers = snippets.keys.sorted()
                var matchingSnippets: [ClipItem] = []
                
                for trigger in sortedTriggers {
                    if let text = snippets[trigger] {
                        let title = text
                        let matchText = title.localizedCaseInsensitiveContains(trimmed)
                        let matchTrigger = trigger.localizedCaseInsensitiveContains(trimmed)
                        let matchCategory = category.localizedCaseInsensitiveContains(trimmed)
                        
                        if trimmed.isEmpty || matchText || matchTrigger || matchCategory {
                            matchingSnippets.append(ClipItem(text: text, isSnippet: true, trigger: trigger, title: title, category: category, systemCommandId: nil, filePath: nil, isDirectory: false))
                        }
                    }
                }
                
                if !matchingSnippets.isEmpty {
                    newRows.append(.header(title: "⚡️ Snippets: \(category)"))
                    for item in matchingSnippets {
                        newRows.append(.item(item))
                    }
                }
            }
        }
        
        // 5. Process contacts (query must be at least 2 characters)
        if trimmed.count >= 2 {
            let matchingContacts = fetchContacts(query: trimmed)
            if !matchingContacts.isEmpty {
                newRows.append(.header(title: "👥 Contacts"))
                for item in matchingContacts {
                    newRows.append(.item(item))
                }
            }
        }
        
        filteredRows = newRows
        tableView.reloadData()
        
        // Select first selectable row if available
        if let firstSelectable = filteredRows.firstIndex(where: {
            if case .item = $0 { return true }
            return false
        }) {
            tableView.selectRowIndexes(IndexSet(integer: firstSelectable), byExtendingSelection: false)
            tableView.scrollRowToVisible(firstSelectable)
        }
    }
    
    func fetchContacts(query: String) -> [ClipItem] {
        let lowerQuery = query.lowercased()
        let queryWords = lowerQuery.split(separator: " ").map { String($0) }
        if queryWords.isEmpty { return [] }
        
        let filtered = allContactsCache.filter { contactItem in
            return queryWords.allSatisfy { contactItem.searchString.contains($0) }
        }
        
        return filtered.map { $0.item }
    }

    func loadContactsCache() {
        let store = CNContactStore()
        let authorizationStatus = CNContactStore.authorizationStatus(for: .contacts)
        guard authorizationStatus == .authorized else { return }
        
        let keysToFetch = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactNicknameKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor
        ]
        
        let request = CNContactFetchRequest(keysToFetch: keysToFetch)
        DispatchQueue.global(qos: .background).async { [weak self] in
            var list: [ContactClipItem] = []
            do {
                try store.enumerateContacts(with: request) { contact, _ in
                    let given = contact.givenName
                    let family = contact.familyName
                    let nickname = contact.nickname
                    let fullName = "\(given) \(family)".trimmingCharacters(in: .whitespaces)
                    let nameToUse = fullName.isEmpty ? (nickname.isEmpty ? "Unknown" : nickname) : fullName
                    
                    let orgName = contact.organizationName
                    let orgStr = orgName.isEmpty ? "" : " [\(orgName)]"
                    
                    var searchParts = [given, family, fullName, nickname, orgName]
                    for phone in contact.phoneNumbers {
                        searchParts.append(phone.value.stringValue)
                    }
                    for email in contact.emailAddresses {
                        searchParts.append(email.value as String)
                    }
                    let contactSearchString = searchParts.filter { !$0.isEmpty }.joined(separator: " ").lowercased()
                    
                    // Add phone numbers
                    for phone in contact.phoneNumbers {
                        let number = phone.value.stringValue
                        let rawLabel = phone.label ?? ""
                        let localizedLabel = CNLabeledValue<NSString>.localizedString(forLabel: rawLabel)
                        
                        let title = "👤 \(nameToUse)\(orgStr) (\(localizedLabel)): \(number)"
                        let item = ClipItem(text: number, isSnippet: false, trigger: nil, title: title, category: "Contacts")
                        list.append(ContactClipItem(item: item, searchString: contactSearchString))
                    }
                    
                    // Add emails
                    for email in contact.emailAddresses {
                        let address = email.value as String
                        let rawLabel = email.label ?? ""
                        let localizedLabel = CNLabeledValue<NSString>.localizedString(forLabel: rawLabel)
                        
                        let title = "✉️ \(nameToUse)\(orgStr) (\(localizedLabel)): \(address)"
                        let item = ClipItem(text: address, isSnippet: false, trigger: nil, title: title, category: "Contacts")
                        list.append(ContactClipItem(item: item, searchString: contactSearchString))
                    }
                }
                
                DispatchQueue.main.async {
                    self?.allContactsCache = list
                    logMessage("Loaded \(list.count) contact items into cache.")
                    if self?.window.isVisible == true {
                        self?.updateAllItems()
                    }
                }
            } catch {
                logMessage("Failed to load contacts cache: \(error)")
            }
        }
    }



    
    // ----------------------------------------------------
    // Action handlers
    // ----------------------------------------------------
    // Helper to extract unique variables in [[var]] format
    func extractVariables(from text: String) -> [String] {
        var variables: [String] = []
        let pattern = "\\[\\[([^\\]]+)\\]\\]"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return []
        }
        
        let nsString = text as NSString
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))
        
        for match in matches {
            if match.numberOfRanges > 1 {
                let varName = nsString.substring(with: match.range(at: 1))
                if !variables.contains(varName) {
                    variables.append(varName)
                }
            }
        }
        return variables
    }
    
    // Helper to show modal input dialog
    func showInputDialog(title: String, prompt: String, defaultValue: String = "") -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = prompt
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        
        let inputTextField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        inputTextField.stringValue = defaultValue
        alert.accessoryView = inputTextField
        
        // Set focus to the text field when alert is shown
        alert.window.initialFirstResponder = inputTextField
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            return inputTextField.stringValue
        }
        return nil
    }

    func selectAndPasteShortcut(number: Int) {
        var itemIndex = 0
        for (rowIdx, row) in filteredRows.enumerated() {
            if case .item = row {
                itemIndex += 1
                if itemIndex == number {
                    selectAndPaste(index: rowIdx)
                    return
                }
            }
        }
    }

    func deleteSelectedHistoryItem() {
        let selectedRow = tableView.selectedRow
        guard selectedRow >= 0 && selectedRow < filteredRows.count else { return }
        guard case .item(let item) = filteredRows[selectedRow] else { return }
        
        // Only allow deleting clipboard history items, not snippets
        guard !item.isSnippet else { return }
        
        // Remove from clipboardHistory
        if let idx = clipboardHistory.firstIndex(of: item.text) {
            clipboardHistory.remove(at: idx)
            saveHistory()
            
            // Reload and filter items keeping the current search text
            filterItems(query: searchField.stringValue)
            
            // Select the same row (or the next selectable row)
            if selectedRow < filteredRows.count {
                // Check if the current row is selectable
                if case .item = filteredRows[selectedRow] {
                    tableView.selectRowIndexes(IndexSet(integer: selectedRow), byExtendingSelection: false)
                } else {
                    // Try to find the next selectable row
                    var nextSelectable = selectedRow
                    while nextSelectable < filteredRows.count {
                        if case .item = filteredRows[nextSelectable] {
                            tableView.selectRowIndexes(IndexSet(integer: nextSelectable), byExtendingSelection: false)
                            break
                        }
                        nextSelectable += 1
                    }
                }
            } else {
                // Select the last selectable row
                if let lastSelectable = filteredRows.enumerated().reversed().first(where: {
                    if case .item = $1 { return true }
                    return false
                }) {
                    tableView.selectRowIndexes(IndexSet(integer: lastSelectable.offset), byExtendingSelection: false)
                }
            }
        }
    }

    func checkTriggers(buffer: String) -> String? {
        for category in customSnippets.keys {
            if let snippets = customSnippets[category] {
                for trigger in snippets.keys {
                    if trigger.hasPrefix(":") && buffer.hasSuffix(trigger) {
                        return trigger
                    }
                }
            }
        }
        return nil
    }
    
    func expandSnippet(trigger: String, deleteCount: Int) {
        var textToPaste: String? = nil
        for category in customSnippets.keys {
            if let snippets = customSnippets[category], let text = snippets[trigger] {
                textToPaste = text
                break
            }
        }
        
        guard var text = textToPaste else { return }
        
        // Evaluate dynamic snippets
        if trigger == ":date" {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            text = formatter.string(from: Date())
        } else if trigger == ":time" {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss"
            text = formatter.string(from: Date())
        }
        
        // Hide window if open
        DispatchQueue.main.async {
            self.hideWindow()
        }
        
        let backspacesToDelete = deleteCount - 1
        
        DispatchQueue.main.async {
            for _ in 0..<backspacesToDelete {
                let bsDown = CGEvent(keyboardEventSource: nil, virtualKey: 51, keyDown: true)
                let bsUp = CGEvent(keyboardEventSource: nil, virtualKey: 51, keyDown: false)
                bsDown?.post(tap: .cgSessionEventTap)
                bsUp?.post(tap: .cgSessionEventTap)
            }
            
            // Wait 0.1s for backspaces to register, then paste
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.pasteDirectly(text: text)
            }
        }
    }

    func selectAndPaste(index: Int) {
        guard index >= 0 && index < filteredRows.count else { return }
        guard case .item(let item) = filteredRows[index] else { return }
        
        // 1. Check if this is a file system item
        if let filePath = item.filePath {
            if item.isDirectory {
                // Drill down into folder
                let newPath = filePath.hasSuffix("/") ? filePath : filePath + "/"
                let displayPath = newPath.replacingOccurrences(of: NSHomeDirectory(), with: "~")
                searchField.stringValue = displayPath
                filterItems(query: displayPath)
                return
            } else {
                // Open file with default application
                hideWindow()
                NSWorkspace.shared.open(URL(fileURLWithPath: filePath))
                return
            }
        }
        
        // 2. Check if this is a system command
        if let commandId = item.systemCommandId {
            hideWindow()
            if let command = SystemCommands.shared.allCommands.first(where: { $0.id == commandId }) {
                logMessage("Executing system command: \(command.name)")
                command.execute()
            }
            return
        }
        
        var textToPaste = item.text
        
        // Dynamic snippet evaluation
        if item.isSnippet {
            if item.trigger == ":date" {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd"
                textToPaste = formatter.string(from: Date())
            } else if item.trigger == ":time" {
                let formatter = DateFormatter()
                formatter.dateFormat = "HH:mm:ss"
                textToPaste = formatter.string(from: Date())
            }
        }
        
        // Hide main window first so the target window gets focus back
        hideWindow()
        
        pasteDirectly(text: textToPaste)
    }

    func pasteDirectly(text: String) {
        var textToPaste = text
        
        // Check for variable prompts
        let variables = extractVariables(from: textToPaste)
        if !variables.isEmpty {
            // Activate our app to show dialogs on top
            NSApp.activate(ignoringOtherApps: true)
            
            var replacements: [String: String] = [:]
            for variable in variables {
                let prompt = "Sisesta väärtus muutujale: \(variable)"
                if let value = showInputDialog(title: "Snippet muutuja", prompt: prompt, defaultValue: "") {
                    replacements[variable] = value
                } else {
                    // Abort on cancel
                    return
                }
            }
            
            // Replace variables
            for (variable, value) in replacements {
                let placeholder = "[[\(variable)]]"
                textToPaste = textToPaste.replacingOccurrences(of: placeholder, with: value)
            }
        }
        
        // Copy selected item to pasteboard
        let pasteboard = NSPasteboard.general
        pasteboard.declareTypes([.string], owner: nil)
        pasteboard.setString(textToPaste, forType: .string)
        
        // Wait 0.15s for target app to gain focus, then post Command-V
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            let vDown = CGEvent(keyboardEventSource: nil, virtualKey: 0x09, keyDown: true)
            vDown?.flags = .maskCommand
            let vUp = CGEvent(keyboardEventSource: nil, virtualKey: 0x09, keyDown: false)
            vUp?.flags = .maskCommand
            
            vDown?.post(tap: .cgSessionEventTap)
            vUp?.post(tap: .cgSessionEventTap)
        }
    }
    
    @objc func editSnippetsFile() {
        NSWorkspace.shared.open(snippetsFile)
    }
    
    @objc func clearHistory() {
        clipboardHistory.removeAll()
        saveHistory()
        updateAllItems()
    }
    
    @objc func quitApp() {
        NSApplication.shared.terminate(nil)
    }
    
    @objc func tableDoubleClicked() {
        let clickedRow = tableView.clickedRow
        if clickedRow >= 0 {
            selectAndPaste(index: clickedRow)
        }
    }
    
    // ----------------------------------------------------
    // Text Field Delegate
    // ----------------------------------------------------
    func controlTextDidChange(_ obj: Notification) {
        filterItems(query: searchField.stringValue)
    }
    
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.moveDown(_:)) {
            let selectedRow = tableView.selectedRow
            var nextRow = selectedRow + 1
            while nextRow < filteredRows.count {
                if case .item = filteredRows[nextRow] {
                    tableView.selectRowIndexes(IndexSet(integer: nextRow), byExtendingSelection: false)
                    tableView.scrollRowToVisible(nextRow)
                    break
                }
                nextRow += 1
            }
            return true
        } else if commandSelector == #selector(NSResponder.moveUp(_:)) {
            let selectedRow = tableView.selectedRow
            var prevRow = selectedRow - 1
            while prevRow >= 0 {
                if case .item = filteredRows[prevRow] {
                    tableView.selectRowIndexes(IndexSet(integer: prevRow), byExtendingSelection: false)
                    tableView.scrollRowToVisible(prevRow)
                    break
                }
                prevRow -= 1
            }
            return true
        } else if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            let selectedRow = tableView.selectedRow
            if selectedRow >= 0 {
                selectAndPaste(index: selectedRow)
            }
            return true
        } else if commandSelector == #selector(NSResponder.insertTab(_:)) {
            // Tab key: If current item is a directory or path item, drill down into it!
            let selectedRow = tableView.selectedRow
            if selectedRow >= 0 && selectedRow < filteredRows.count {
                if case .item(let item) = filteredRows[selectedRow] {
                    if let filePath = item.filePath, item.isDirectory {
                        let newPath = filePath.hasSuffix("/") ? filePath : filePath + "/"
                        let displayPath = newPath.replacingOccurrences(of: NSHomeDirectory(), with: "~")
                        searchField.stringValue = displayPath
                        filterItems(query: displayPath)
                        return true
                    }
                }
            }
            return true
        } else if commandSelector == #selector(NSResponder.deleteBackward(_:)) {
            // Backspace key: If in folder navigation and ending with "/", jump UP one folder level instantly
            let current = searchField.stringValue
            if (current.hasPrefix("~") || current.hasPrefix("/")) && current.hasSuffix("/") {
                if current == "~/" || current == "/" {
                    searchField.stringValue = ""
                    filterItems(query: "")
                    return true
                }
                
                var parts = current.split(separator: "/", omittingEmptySubsequences: true).map { String($0) }
                if parts.count > 1 {
                    parts.removeLast()
                    let isAbsolute = current.hasPrefix("/")
                    let newPath = (isAbsolute ? "/" : "") + parts.joined(separator: "/") + "/"
                    searchField.stringValue = newPath
                    filterItems(query: newPath)
                    return true
                } else if parts.count == 1 && current.hasPrefix("/") {
                    searchField.stringValue = "/"
                    filterItems(query: "/")
                    return true
                } else {
                    searchField.stringValue = ""
                    filterItems(query: "")
                    return true
                }
            }
            return false
        } else if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            hideWindow()
            return true
        }
        return false
    }
    
    // ----------------------------------------------------
    // Table View Data Source & Delegate
    // ----------------------------------------------------
    func numberOfRows(in tableView: NSTableView) -> Int {
        return filteredRows.count
    }
    
    func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
        switch filteredRows[row] {
        case .header: return true
        case .item: return false
        }
    }
    
    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        switch filteredRows[row] {
        case .header: return false
        case .item: return true
        }
    }
    
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        switch filteredRows[row] {
        case .header: return 24
        case .item: return 32
        }
    }
    
    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        let rowData = filteredRows[row]
        
        if tableColumn?.identifier.rawValue == "text" {
            switch rowData {
            case .header(let title):
                return title
            case .item(let item):
                let titleText = item.title.replacingOccurrences(of: "\n", with: " ")
                let displayText = titleText.count > 65 ? String(titleText.prefix(65)) + "..." : titleText
                if item.isSnippet {
                    return "    [\(item.trigger ?? "")] \(displayText)"
                }
                return "    \(displayText)"
            }
        } else {
            switch rowData {
            case .header:
                return ""
            case .item:
                // Find the index of this item among all selectable items in filteredRows
                var itemIndex = 0
                for i in 0...row {
                    if case .item = filteredRows[i] {
                        if i == row {
                            if itemIndex < 9 {
                                return "⌘\(itemIndex + 1)"
                            }
                            return ""
                        }
                        itemIndex += 1
                    }
                }
                return ""
            }
        }
    }
}

var strongDelegate: AppDelegate?

let app = NSApplication.shared
let delegateInstance = AppDelegate()
strongDelegate = delegateInstance
app.delegate = delegateInstance
app.run()
