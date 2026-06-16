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
}

struct ContactClipItem {
    let item: ClipItem
    let searchString: String
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
    
    func setupEventTap() {
        let eventMask = (1 << CGEventType.keyDown.rawValue)
        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: myEventTapCallback,
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        ) else {
            logMessage("Failed to create event tap - please check Accessibility permissions!")
            return
        }
        
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
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
        NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
        NSApp.activate(ignoringOtherApps: true)
        
        // Make window key and front
        window.makeKeyAndOrderFront(nil)
        
        DispatchQueue.main.async {
            NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
            NSApp.activate(ignoringOtherApps: true)
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
    
    func filterItems(query: String) {
        var newRows: [TableRow] = []
        
        // 1. Process clipboard history (now first)
        let matchingHistory: [ClipItem]
        if query.isEmpty {
            matchingHistory = clipboardHistory.map { ClipItem(text: $0, isSnippet: false, trigger: nil, title: $0, category: nil) }
        } else {
            matchingHistory = clipboardHistory
                .filter { $0.localizedCaseInsensitiveContains(query) }
                .map { ClipItem(text: $0, isSnippet: false, trigger: nil, title: $0, category: nil) }
        }
        
        if !matchingHistory.isEmpty {
            newRows.append(.header(title: "📋 Clipboard History"))
            for item in matchingHistory {
                newRows.append(.item(item))
            }
        }
        
        // 2. Process custom snippets by category
        let sortedCategories = customSnippets.keys.sorted()
        for category in sortedCategories {
            if let snippets = customSnippets[category] {
                let sortedTriggers = snippets.keys.sorted()
                var matchingSnippets: [ClipItem] = []
                
                for trigger in sortedTriggers {
                    if let text = snippets[trigger] {
                        let title = text
                        let matchText = title.localizedCaseInsensitiveContains(query)
                        let matchTrigger = trigger.localizedCaseInsensitiveContains(query)
                        let matchCategory = category.localizedCaseInsensitiveContains(query)
                        
                        if query.isEmpty || matchText || matchTrigger || matchCategory {
                            matchingSnippets.append(ClipItem(text: text, isSnippet: true, trigger: trigger, title: title, category: category))
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
        
        // 3. Process contacts (query must be at least 2 characters)
        if query.count >= 2 {
            let matchingContacts = fetchContacts(query: query)
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
