import AppKit
import SwiftUI
import Combine
import UserNotifications

// MARK: - Custom Progress Bar Menu Item View

class ProgressMenuItemView: NSView {
    let bucketName: String
    let rawName: String
    let utilization: Double
    let timeRemaining: String
    let source: String

    var brandColor: NSColor {
        if rawName.hasPrefix("chatgpt") {
            return NSColor(red: 16/255, green: 163/255, blue: 127/255, alpha: 1.0)
        } else if rawName.hasPrefix("gemini") {
            return NSColor(red: 26/255, green: 115/255, blue: 232/255, alpha: 1.0)
        } else if rawName.hasPrefix("perplexity") {
            return NSColor(red: 25/255, green: 161/255, blue: 183/255, alpha: 1.0)
        } else if rawName.hasPrefix("antigravity") {
            return NSColor(red: 142/255, green: 68/255, blue: 173/255, alpha: 1.0)
        } else {
            return .systemOrange
        }
    }
    
    var barColor: NSColor {
        if utilization >= 90 { return .systemRed }
        else if utilization >= 75 { return .systemOrange }
        else { return brandColor }
    }

    // Honest provenance tag shown next to the title.
    var sourceTag: String {
        switch source {
        case "live_subscription": return "LIVE"
        case "live_local": return "LOCAL"
        case "live_api_cost": return "API $"
        case "extension": return "EXT"
        case "manual": return "MANUAL"
        default: return "LIVE"
        }
    }

    var sourceTagColor: NSColor {
        switch source {
        case "manual": return .tertiaryLabelColor
        case "extension": return .systemTeal
        default: return .systemGreen
        }
    }
    
    init(bucketName: String, rawName: String, utilization: Double, timeRemaining: String, source: String) {
        self.bucketName = bucketName
        self.rawName = rawName
        self.utilization = utilization
        self.timeRemaining = timeRemaining
        self.source = source
        super.init(frame: NSRect(x: 0, y: 0, width: 280, height: 44))
    }
    
    required init?(coder: NSCoder) { fatalError() }
    
    override var intrinsicContentSize: NSSize {
        return NSSize(width: 280, height: 44)
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        let pad: CGFloat = 16
        let rPad: CGFloat = 16
        
        // Row 1: Title (left) + source tag + Percentage (right, bold, colored)
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.labelColor
        ]
        let titleAS = NSAttributedString(string: bucketName, attributes: titleAttrs)
        titleAS.draw(at: NSPoint(x: pad, y: bounds.height - 20))

        // Source provenance tag (LIVE / LOCAL / API $ / MANUAL / EXT) right after the title.
        let tagAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 8, weight: .bold),
            .foregroundColor: sourceTagColor
        ]
        NSAttributedString(string: sourceTag, attributes: tagAttrs)
            .draw(at: NSPoint(x: pad + titleAS.size().width + 6, y: bounds.height - 19))
        
        let pctStr = "\(Int(utilization))%"
        let pctAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .bold),
            .foregroundColor: barColor
        ]
        let pctAS = NSAttributedString(string: pctStr, attributes: pctAttrs)
        let pctSize = pctAS.size()
        pctAS.draw(at: NSPoint(x: bounds.width - rPad - pctSize.width, y: bounds.height - 20))
        
        // Row 2: Progress bar (left) + Time remaining (right)
        let timeAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        let timeAS = NSAttributedString(string: timeRemaining, attributes: timeAttrs)
        let timeSize = timeAS.size()
        timeAS.draw(at: NSPoint(x: bounds.width - rPad - timeSize.width, y: 5))
        
        // Progress bar
        let barY: CGFloat = 7
        let barH: CGFloat = 5
        let barW = bounds.width - pad - rPad - timeSize.width - 12
        
        // Background
        let bgRect = NSRect(x: pad, y: barY, width: barW, height: barH)
        let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: 2.5, yRadius: 2.5)
        NSColor.quaternaryLabelColor.setFill()
        bgPath.fill()
        
        // Fill
        let fillW = barW * CGFloat(min(utilization / 100.0, 1.0))
        if fillW > 0 {
            let fillRect = NSRect(x: pad, y: barY, width: fillW, height: barH)
            let fillPath = NSBezierPath(roundedRect: fillRect, xRadius: 2.5, yRadius: 2.5)
            barColor.setFill()
            fillPath.fill()
        }
    }
}

// MARK: - Settings Window Controller

class SettingsWindowController: NSWindowController {
    var appState: AppState
    
    init(appState: AppState) {
        self.appState = appState
        let view = SettingsView(state: appState)
        let hosting = NSHostingController(rootView: view)
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 580, height: 420),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = hosting
        window.title = "Claude Usage Settings"
        window.center()
        window.isReleasedWhenClosed = false
        window.level = .floating
        
        super.init(window: window)
    }
    
    required init?(coder: NSCoder) { fatalError() }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, UNUserNotificationCenterDelegate {
    var statusItem: NSStatusItem?
    var appState = AppState()
    var settingsWindowController: SettingsWindowController?
    var pollingTimer: Timer?
    var cancellables = Set<AnyCancellable>()
    var lastNotifiedUtilization: [String: Double] = [:]
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        
        UNUserNotificationCenter.current().delegate = self
        requestNotificationPermission()
        
        setupMainMenu()
        
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            button.image = createMenuBarIcon(withChar: "C")
            button.imagePosition = .imageLeft
            button.title = "--"
        }
        
        let menu = NSMenu()
        menu.delegate = self
        statusItem?.menu = menu
        
        setupSubscribers()
        
        NotificationCenter.default.addObserver(self, selector: #selector(resetPollingTimer), name: Notification.Name("ResetPollingTimer"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(updateMenuBarDisplay), name: Notification.Name("UpdateMenuBarText"), object: nil)
        
        startPollingTimer()
        appState.refreshUsage()
    }
    
    func setupMainMenu() {
        let mainMenu = NSMenu()
        
        // App Menu
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        appMenu.addItem(withTitle: "About Claude Usage", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Quit Claude Usage", action: #selector(quitClicked), keyEquivalent: "")
        
        // Edit Menu (crucial for supporting Command+V pasting in accessory app window)
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenuItem.submenu = editMenu
        
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        
        NSApp.mainMenu = mainMenu
    }
    
    // MARK: - Menu Bar Icon
    
    func createMenuBarIcon(withChar char: String) -> NSImage {
        let size = NSSize(width: 14, height: 14)
        let image = NSImage(size: size, flipped: false) { rect in
            let font = NSFont.systemFont(ofSize: 11, weight: .heavy)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.black
            ]
            let str = NSAttributedString(string: char, attributes: attrs)
            let strSize = str.size()
            let x = (rect.width - strSize.width) / 2
            let y = (rect.height - strSize.height) / 2
            str.draw(at: NSPoint(x: x, y: y))
            return true
        }
        image.isTemplate = true
        return image
    }
    
    // MARK: - Subscribers
    
    func setupSubscribers() {
        appState.$usageBuckets
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateMenuBarDisplay()
                self?.checkThresholdsAndNotify()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Menu Bar Display Helpers
    
    func getSessionBucket() -> AppState.UsageBucket? {
        return appState.usageBuckets.first(where: { $0.name == "five_hour" })
    }
    
    func getWeeklyBucket() -> AppState.UsageBucket? {
        return appState.usageBuckets.first(where: { $0.name == "seven_day" })
    }
    
    func colorForUtilization(_ util: Double) -> NSColor {
        if util >= appState.thresholdNotification { return .systemRed }
        else if util >= 60 { return .systemOrange }
        else { return .labelColor }
    }
    
    func getPrimaryDisplayValues() -> (title: String, percentage: Int, detailText: String, brandChar: String) {
        let provider = appState.primaryProvider
        if provider == "claude" {
            let session = getSessionBucket()
            let pct = session.map { Int($0.utilization) } ?? 0
            let weekly = getWeeklyBucket()
            let weeklyPct = weekly.map { Int($0.utilization) } ?? 0
            return ("Claude", pct, "W:\(weeklyPct)%", "C")
        } else if provider == "chatgpt" {
            let bucket = appState.usageBuckets.first(where: { $0.name == "chatgpt_api" })
            let pct = bucket.map { Int($0.utilization) } ?? 0
            return ("ChatGPT", pct, bucket?.resetsAt ?? "$--", "G")
        } else if provider == "gemini" {
            let bucket = appState.usageBuckets.first(where: { $0.name == "gemini_api" })
            let pct = bucket.map { Int($0.utilization) } ?? 0
            return ("Gemini", pct, "\(Int(appState.geminiCurrentUsage)) req", "M")
        } else if provider == "perplexity" {
            let bucket = appState.usageBuckets.first(where: { $0.name == "perplexity_api" })
            let pct = bucket.map { Int($0.utilization) } ?? 0
            return ("Perplexity", pct, bucket?.resetsAt ?? "$--", "P")
        } else if provider == "antigravity" {
            let bucket = appState.usageBuckets.first(where: { $0.name == "antigravity_usage" })
            let pct = bucket.map { Int($0.utilization) } ?? 0
            return ("Antigravity", pct, "\(Int(appState.antigravityCurrentUsage)) q", "A")
        } else {
            let claudeSession = getSessionBucket()
            let cPct = claudeSession.map { Int($0.utilization) } ?? 0
            if let other = appState.usageBuckets.first(where: { $0.name != "five_hour" && $0.name != "seven_day" && $0.name != "extra_usage" }) {
                return ("Hybrid", cPct, "\(other.displayName.prefix(3)):\(Int(other.utilization))%", "H")
            } else {
                let weekly = getWeeklyBucket()
                let weeklyPct = weekly.map { Int($0.utilization) } ?? 0
                return ("Hybrid", cPct, "W:\(weeklyPct)%", "H")
            }
        }
    }
    
    @objc func updateMenuBarDisplay() {
        guard let button = statusItem?.button else { return }
        
        let (_, pPct, pDetail, pChar) = getPrimaryDisplayValues()
        let hasData = !appState.usageBuckets.isEmpty
        
        // Icon
        if appState.showMenuBarIcon {
            button.image = createMenuBarIcon(withChar: pChar)
            button.imagePosition = .imageLeft
        } else {
            button.image = nil
            button.imagePosition = .noImage
        }
        
        switch appState.displayMode {
        case "stacked":
            let style = NSMutableParagraphStyle()
            style.alignment = appState.showMenuBarIcon ? .left : .center
            style.lineHeightMultiple = 0.85
            style.minimumLineHeight = 9.0
            style.maximumLineHeight = 10.0
            
            if !hasData {
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .semibold),
                    .foregroundColor: NSColor.secondaryLabelColor,
                    .paragraphStyle: style,
                    .baselineOffset: -2.0
                ]
                button.attributedTitle = NSAttributedString(string: "\(pChar): --% \n--% ", attributes: attrs)
            } else {
                let text = NSMutableAttributedString()
                text.append(NSAttributedString(string: "\(pChar):\(pPct)% \n", attributes: [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .bold),
                    .foregroundColor: colorForUtilization(Double(pPct)),
                    .paragraphStyle: style,
                    .baselineOffset: -1.5
                ]))
                text.append(NSAttributedString(string: "\(pDetail) ", attributes: [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium),
                    .foregroundColor: NSColor.secondaryLabelColor,
                    .paragraphStyle: style,
                    .baselineOffset: -2.0
                ]))
                button.attributedTitle = text
            }
            
        case "compact":
            if !hasData {
                button.attributedTitle = NSAttributedString(string: "\(pChar):--% \(pDetail)", attributes: [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
                    .foregroundColor: NSColor.secondaryLabelColor
                ])
            } else {
                button.attributedTitle = NSAttributedString(string: "\(pChar):\(pPct)% \(pDetail)", attributes: [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
                    .foregroundColor: colorForUtilization(Double(pPct))
                ])
            }
            
        case "session":
            if !hasData {
                button.attributedTitle = NSAttributedString(string: "--%", attributes: [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
                    .foregroundColor: NSColor.secondaryLabelColor
                ])
            } else {
                button.attributedTitle = NSAttributedString(string: "\(pPct)%", attributes: [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .bold),
                    .foregroundColor: colorForUtilization(Double(pPct))
                ])
            }
            
        case "icon_only":
            button.title = ""
            
        default:
            button.title = "\(pChar): \(pPct)%"
        }
    }
    
    // MARK: - Menu Delegate (Dynamic Menu with Progress Bars)
    
    func menuWillOpen(_ menu: NSMenu) {
        menu.removeAllItems()
        
        let headerItem = NSMenuItem(title: "AI Models Usage Tracker", action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        headerItem.attributedTitle = NSAttributedString(string: "AI Models Usage Tracker", attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .bold),
            .foregroundColor: NSColor.labelColor
        ])
        menu.addItem(headerItem)
        
        if appState.usageBuckets.isEmpty {
            menu.addItem(NSMenuItem.separator())
            if let error = appState.errorMessage {
                let errorItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
                errorItem.isEnabled = false
                errorItem.attributedTitle = NSAttributedString(string: "⚠ \(error)", attributes: [
                    .font: NSFont.systemFont(ofSize: 10),
                    .foregroundColor: NSColor.systemRed
                ])
                menu.addItem(errorItem)
            } else {
                let noDataItem = NSMenuItem(title: "No usage data yet", action: nil, keyEquivalent: "")
                noDataItem.isEnabled = false
                menu.addItem(noDataItem)
            }
        } else {
            func addProviderHeader(title: String, color: NSColor) {
                menu.addItem(NSMenuItem.separator())
                let header = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                header.isEnabled = false
                header.attributedTitle = NSAttributedString(string: title, attributes: [
                    .font: NSFont.systemFont(ofSize: 10, weight: .bold),
                    .foregroundColor: color
                ])
                menu.addItem(header)
            }
            
            for provider in appState.providerOrder {
                switch provider {
                case "claude":
                    let claudeBuckets = appState.usageBuckets.filter { 
                        !$0.name.hasPrefix("chatgpt") && !$0.name.hasPrefix("gemini") &&
                        !$0.name.hasPrefix("perplexity") && !$0.name.hasPrefix("antigravity")
                    }
                    if !claudeBuckets.isEmpty {
                        addProviderHeader(title: "Claude (Anthropic)", color: .systemOrange)
                        for bucket in claudeBuckets {
                            let progressView = ProgressMenuItemView(
                                bucketName: bucket.displayName,
                                rawName: bucket.name,
                                utilization: bucket.utilization,
                                timeRemaining: bucket.timeRemainingString,
                                source: bucket.source
                            )
                            let menuItem = NSMenuItem()
                            menuItem.view = progressView
                            menu.addItem(menuItem)
                        }
                    }
                case "chatgpt":
                    let chatgptBuckets = appState.usageBuckets.filter { $0.name.hasPrefix("chatgpt") }
                    if !chatgptBuckets.isEmpty {
                        addProviderHeader(title: "ChatGPT (OpenAI)", color: NSColor(red: 16/255, green: 163/255, blue: 127/255, alpha: 1.0))
                        for bucket in chatgptBuckets {
                            let progressView = ProgressMenuItemView(
                                bucketName: bucket.displayName,
                                rawName: bucket.name,
                                utilization: bucket.utilization,
                                timeRemaining: bucket.timeRemainingString,
                                source: bucket.source
                            )
                            let menuItem = NSMenuItem()
                            menuItem.view = progressView
                            menu.addItem(menuItem)
                        }
                    }
                case "gemini":
                    let geminiBuckets = appState.usageBuckets.filter { $0.name.hasPrefix("gemini") }
                    if !geminiBuckets.isEmpty {
                        addProviderHeader(title: "Gemini (Google)", color: NSColor(red: 26/255, green: 115/255, blue: 232/255, alpha: 1.0))
                        for bucket in geminiBuckets {
                            let progressView = ProgressMenuItemView(
                                bucketName: bucket.displayName,
                                rawName: bucket.name,
                                utilization: bucket.utilization,
                                timeRemaining: bucket.timeRemainingString,
                                source: bucket.source
                            )
                            let menuItem = NSMenuItem()
                            menuItem.view = progressView
                            menu.addItem(menuItem)
                        }
                    }
                case "perplexity":
                    let perplexityBuckets = appState.usageBuckets.filter { $0.name.hasPrefix("perplexity") }
                    if !perplexityBuckets.isEmpty {
                        addProviderHeader(title: "Perplexity", color: NSColor(red: 25/255, green: 161/255, blue: 183/255, alpha: 1.0))
                        for bucket in perplexityBuckets {
                            let progressView = ProgressMenuItemView(
                                bucketName: bucket.displayName,
                                rawName: bucket.name,
                                utilization: bucket.utilization,
                                timeRemaining: bucket.timeRemainingString,
                                source: bucket.source
                            )
                            let menuItem = NSMenuItem()
                            menuItem.view = progressView
                            menu.addItem(menuItem)
                        }
                    }
                case "antigravity":
                    let antigravityBuckets = appState.usageBuckets.filter { $0.name.hasPrefix("antigravity") }
                    if !antigravityBuckets.isEmpty {
                        addProviderHeader(title: "Antigravity Agent", color: NSColor(red: 142/255, green: 68/255, blue: 173/255, alpha: 1.0))
                        for bucket in antigravityBuckets {
                            let progressView = ProgressMenuItemView(
                                bucketName: bucket.displayName,
                                rawName: bucket.name,
                                utilization: bucket.utilization,
                                timeRemaining: bucket.timeRemainingString,
                                source: bucket.source
                            )
                            let menuItem = NSMenuItem()
                            menuItem.view = progressView
                            menu.addItem(menuItem)
                        }
                    }
                default:
                    break
                }
            }
        }
        
        menu.addItem(NSMenuItem.separator())
        
        // Last updated
        if let lastFetch = appState.lastFetchTime {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            let lastItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
            lastItem.isEnabled = false
            lastItem.attributedTitle = NSAttributedString(string: "Updated: \(formatter.string(from: lastFetch))", attributes: [
                .font: NSFont.systemFont(ofSize: 10),
                .foregroundColor: NSColor.tertiaryLabelColor
            ])
            menu.addItem(lastItem)
        }
        
        // Actions
        let refreshItem = NSMenuItem(title: "Refresh Now", action: #selector(refreshClicked), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)
        
        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(settingsClicked), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "Quit Claude Usage", action: #selector(quitClicked), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }
    
    // MARK: - Actions
    
    @objc func refreshClicked() {
        appState.refreshUsage()
    }
    
    @objc func settingsClicked() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(appState: appState)
        }
        settingsWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc func quitClicked() {
        NSApplication.shared.terminate(self)
    }
    
    // MARK: - Polling
    
    @objc func startPollingTimer() {
        pollingTimer?.invalidate()
        pollingTimer = Timer.scheduledTimer(withTimeInterval: appState.pollingInterval, repeats: true) { [weak self] _ in
            self?.appState.refreshUsage()
        }
    }
    
    @objc func resetPollingTimer() {
        startPollingTimer()
    }
    
    // MARK: - Notifications
    
    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
    
    func checkThresholdsAndNotify() {
        guard appState.enableNotifications else { return }
        
        for bucket in appState.usageBuckets {
            let utilization = bucket.utilization
            let threshold = appState.thresholdNotification
            
            if utilization >= threshold {
                let lastVal = lastNotifiedUtilization[bucket.name] ?? 0.0
                if lastVal < threshold || (utilization - lastVal) >= 5.0 {
                    lastNotifiedUtilization[bucket.name] = utilization
                    
                    let content = UNMutableNotificationContent()
                    content.title = "Claude Limit Warning (\(Int(utilization))%)"
                    content.body = "\(bucket.displayName) is at \(Int(utilization))% capacity. \(bucket.timeRemainingString)."
                    content.sound = .default
                    
                    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
                    let request = UNNotificationRequest(identifier: "ClaudeUsage-\(bucket.name)", content: content, trigger: trigger)
                    UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
                }
            } else {
                if (lastNotifiedUtilization[bucket.name] ?? 0.0) >= threshold {
                    lastNotifiedUtilization[bucket.name] = 0.0
                }
            }
        }
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}

// MARK: - Main Entry Point
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
