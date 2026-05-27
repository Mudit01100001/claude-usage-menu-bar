import AppKit
import SwiftUI
import Combine
import UserNotifications

// MARK: - Custom Progress Bar Menu Item View

class ProgressMenuItemView: NSView {
    let bucketName: String
    let utilization: Double
    let timeRemaining: String
    
    var barColor: NSColor {
        if utilization >= 85 { return .systemRed }
        else if utilization >= 60 { return .systemOrange }
        else { return .systemGreen }
    }
    
    init(bucketName: String, utilization: Double, timeRemaining: String) {
        self.bucketName = bucketName
        self.utilization = utilization
        self.timeRemaining = timeRemaining
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
        
        // Row 1: Title (left) + Percentage (right, bold, colored)
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.labelColor
        ]
        NSAttributedString(string: bucketName, attributes: titleAttrs)
            .draw(at: NSPoint(x: pad, y: bounds.height - 20))
        
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
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 420),
            styleMask: [.titled, .closable, .miniaturizable],
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
            button.image = createMenuBarIcon()
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
        appMenu.addItem(withTitle: "Quit Claude Usage", action: #selector(quitClicked), keyEquivalent: "q")
        
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
    
    func createMenuBarIcon() -> NSImage {
        let size = NSSize(width: 12, height: 12)
        let image = NSImage(size: size, flipped: false) { rect in
            let font = NSFont.systemFont(ofSize: 10, weight: .heavy)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.black
            ]
            let str = NSAttributedString(string: "C", attributes: attrs)
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
    
    // MARK: - Menu Bar Display
    
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
    
    @objc func updateMenuBarDisplay() {
        guard let button = statusItem?.button else { return }
        
        let session = getSessionBucket()
        let weekly = getWeeklyBucket()
        let sessionPct = session.map { Int($0.utilization) } ?? 0
        let weeklyPct = weekly.map { Int($0.utilization) } ?? 0
        let hasData = !appState.usageBuckets.isEmpty
        
        // Icon
        if appState.showMenuBarIcon {
            button.image = createMenuBarIcon()
            button.imagePosition = .imageLeft
        } else {
            button.image = nil
        }
        
        switch appState.displayMode {
        case "stacked":
            // Two-line stacked display like Macs Fan Control
            if !hasData {
                let style = NSMutableParagraphStyle()
                style.alignment = .left
                style.lineHeightMultiple = 0.88
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium),
                    .foregroundColor: NSColor.secondaryLabelColor,
                    .paragraphStyle: style
                ]
                button.attributedTitle = NSAttributedString(string: "S: --%\nW: --%", attributes: attrs)
            } else {
                let style = NSMutableParagraphStyle()
                style.alignment = .left
                style.lineHeightMultiple = 0.88
                
                let text = NSMutableAttributedString()
                text.append(NSAttributedString(string: "S:\(sessionPct)%\n", attributes: [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .bold),
                    .foregroundColor: colorForUtilization(Double(sessionPct)),
                    .paragraphStyle: style
                ]))
                text.append(NSAttributedString(string: "W:\(weeklyPct)%", attributes: [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium),
                    .foregroundColor: colorForUtilization(Double(weeklyPct)),
                    .paragraphStyle: style
                ]))
                button.attributedTitle = text
            }
            
        case "compact":
            // Single line with both: "S:22% W:15%"
            if !hasData {
                button.attributedTitle = NSAttributedString(string: "S:--% W:--%", attributes: [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
                    .foregroundColor: NSColor.secondaryLabelColor
                ])
            } else {
                let maxUtil = max(Double(sessionPct), Double(weeklyPct))
                let color = colorForUtilization(maxUtil)
                button.attributedTitle = NSAttributedString(string: "S:\(sessionPct)% W:\(weeklyPct)%", attributes: [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
                    .foregroundColor: color
                ])
            }
            
        case "session":
            // Just the session percentage
            if !hasData {
                button.attributedTitle = NSAttributedString(string: "--%", attributes: [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
                    .foregroundColor: NSColor.secondaryLabelColor
                ])
            } else {
                button.attributedTitle = NSAttributedString(string: "\(sessionPct)%", attributes: [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .bold),
                    .foregroundColor: colorForUtilization(Double(sessionPct))
                ])
            }
            
        case "icon_only":
            // Just the icon, no text
            button.title = ""
            
        default:
            button.title = "C: \(sessionPct)%"
        }
    }
    
    // MARK: - Menu Delegate (Dynamic Menu with Progress Bars)
    
    func menuWillOpen(_ menu: NSMenu) {
        menu.removeAllItems()
        
        // Header
        let headerItem = NSMenuItem(title: "Claude Session Usage", action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        let headerAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .bold),
            .foregroundColor: NSColor.labelColor
        ]
        headerItem.attributedTitle = NSAttributedString(string: "Claude Session Usage", attributes: headerAttrs)
        menu.addItem(headerItem)
        
        if !appState.usageBuckets.isEmpty {
            let session = getSessionBucket()
            let weekly = getWeeklyBucket()
            let sessionPct = session.map { "\(Int($0.utilization))%" } ?? "--%"
            let weeklyPct = weekly.map { "\(Int($0.utilization))%" } ?? "--%"
            
            let summaryItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
            summaryItem.isEnabled = false
            summaryItem.attributedTitle = NSAttributedString(string: "Usage: Session \(sessionPct) • Weekly \(weeklyPct)", attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .medium),
                .foregroundColor: NSColor.secondaryLabelColor
            ])
            menu.addItem(summaryItem)
        }
        
        menu.addItem(NSMenuItem.separator())
        
        if appState.usageBuckets.isEmpty {
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
            // Progress bar items for each bucket
            for bucket in appState.usageBuckets {
                let progressView = ProgressMenuItemView(
                    bucketName: bucket.displayName,
                    utilization: bucket.utilization,
                    timeRemaining: bucket.timeRemainingString
                )
                let menuItem = NSMenuItem()
                menuItem.view = progressView
                menu.addItem(menuItem)
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
