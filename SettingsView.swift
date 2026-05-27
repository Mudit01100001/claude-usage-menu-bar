import SwiftUI

struct SettingsView: View {
    @ObservedObject var state: AppState
    @State private var selectedTab: String = "dashboard"
    @State private var isVerifying: Bool = false
    @State private var verifySuccess: Bool? = nil
    @State private var verifyError: String? = nil
    
    var body: some View {
        HSplitView {
            // Sidebar Navigation
            VStack(alignment: .leading, spacing: 4) {
                // Header/Title
                HStack(spacing: 6) {
                    Image(systemName: "chart.pie.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.orange)
                    Text("Claude Usage")
                        .font(.system(size: 14, weight: .bold))
                        .lineLimit(1)
                }
                .padding(.horizontal, 10)
                .padding(.top, 14)
                .padding(.bottom, 16)
                
                // Sidebar Buttons
                SidebarButton(title: "Dashboard", icon: "square.grid.2x2.fill", isSelected: selectedTab == "dashboard") {
                    selectedTab = "dashboard"
                }
                
                SidebarButton(title: "Connection", icon: "link", isSelected: selectedTab == "connection") {
                    selectedTab = "connection"
                }
                
                SidebarButton(title: "Display", icon: "rectangle.3.group", isSelected: selectedTab == "display") {
                    selectedTab = "display"
                }
                
                SidebarButton(title: "Settings", icon: "gearshape.fill", isSelected: selectedTab == "settings") {
                    selectedTab = "settings"
                }
                
                Spacer()
                
                // Footer
                VStack(alignment: .leading, spacing: 2) {
                    if let lastTime = state.lastFetchTime {
                        Text("Updated:")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                        Text(lastTime.formatted(date: .omitted, time: .shortened))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                    } else {
                        Text("Never updated")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 12)
            }
            .frame(minWidth: 110, idealWidth: 135, maxWidth: 200)
            .frame(maxHeight: .infinity)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.4))
            
            // Main Content Area
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch selectedTab {
                    case "dashboard":
                        DashboardTabView(state: state)
                    case "connection":
                        ConnectionTabView(
                            state: state,
                            isVerifying: $isVerifying,
                            verifySuccess: $verifySuccess,
                            verifyError: $verifyError
                        )
                    case "display":
                        DisplayTabView(state: state)
                    case "settings":
                        SettingsTabView(state: state)
                    default:
                        EmptyView()
                    }
                }
                .padding(24)
            }
            .frame(minWidth: 350, idealWidth: 425, maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(NSColor.underPageBackgroundColor))
        }
        .frame(width: 560, height: 420)
    }
}

// MARK: - Sidebar Button

struct SidebarButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .frame(width: 14)
                Text(title)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(isSelected ? Color.orange.opacity(0.15) : Color.clear)
            )
            .foregroundColor(isSelected ? .orange : .primary)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
    }
}

// MARK: - Dashboard Tab

struct DashboardTabView: View {
    @ObservedObject var state: AppState
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Usage Dashboard")
                .font(.system(size: 18, weight: .bold))
            
            if state.usageBuckets.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "tray.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary.opacity(0.5))
                        .padding(.top, 20)
                    
                    Text("No usage data available.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    Text("Please set up your connection, then click refresh.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                    
                    Button(action: { state.refreshUsage() }) {
                        HStack(spacing: 6) {
                            if state.isFetching {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                            Text("Refresh Now")
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 12)
                    }
                    .disabled(state.isFetching)
                    .padding(.bottom, 20)
                }
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(NSColor.controlBackgroundColor).opacity(0.5))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
                )
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 16) {
                    ForEach(state.usageBuckets) { bucket in
                        BucketCard(bucket: bucket)
                    }
                }
                
                if let error = state.errorMessage {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Text(error)
                            .font(.system(size: 11))
                            .foregroundColor(.red)
                    }
                    .padding(10)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(6)
                }
            }
        }
    }
}

struct BucketCard: View {
    let bucket: AppState.UsageBucket
    
    var color: Color {
        if bucket.utilization >= 85 {
            return .red
        } else if bucket.utilization >= 60 {
            return .orange
        } else {
            return .green
        }
    }
    
    var body: some View {
        VStack(spacing: 12) {
            Text(bucket.displayName)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            HStack(spacing: 16) {
                // Circular Ring
                ZStack {
                    Circle()
                        .stroke(lineWidth: 6)
                        .opacity(0.1)
                        .foregroundColor(color)
                    
                    Circle()
                        .trim(from: 0.0, to: CGFloat(min(bucket.utilization / 100.0, 1.0)))
                        .stroke(style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
                        .foregroundColor(color)
                        .rotationEffect(Angle(degrees: -90))
                    
                    Text("\(Int(bucket.utilization))%")
                        .font(.system(size: 13, weight: .bold))
                }
                .frame(width: 50, height: 50)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(Int(bucket.utilization))% used")
                        .font(.system(size: 14, weight: .semibold))
                    Text(bucket.timeRemainingString)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
        )
    }
}

// MARK: - Connection Tab

struct ConnectionTabView: View {
    @ObservedObject var state: AppState
    @Binding var isVerifying: Bool
    @Binding var verifySuccess: Bool?
    @Binding var verifyError: String?
    @State private var showSessionKey: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Connection Setup")
                .font(.system(size: 18, weight: .bold))
            
            // Picker
            Picker("Method", selection: $state.selectedMethod) {
                Text("Claude Web Session").tag("web")
                Text("Claude Code CLI").tag("cli")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: state.selectedMethod) { _ in
                verifySuccess = nil
                verifyError = nil
                state.saveSettings()
            }
            
            if state.selectedMethod == "web" {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Secure Web Authentication")
                        .font(.system(size: 13, weight: .semibold))
                    
                    Text("Enter your Claude web session key. It is saved securely in your macOS Keychain and persists across app restarts.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 8) {
                        if showSessionKey {
                            TextField("Paste session key here (sk-ant-sid01-...)", text: $state.sessionKey)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 11, design: .monospaced))
                        } else {
                            SecureField("Paste session key here (sk-ant-sid01-...)", text: $state.sessionKey)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 11, design: .monospaced))
                        }
                        Button(action: { showSessionKey.toggle() }) {
                            Image(systemName: showSessionKey ? "eye.slash" : "eye")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help(showSessionKey ? "Hide key" : "Show key (also enables paste)")
                    }
                    
                    HStack(spacing: 12) {
                        Button(action: verifyAndSaveWebSession) {
                            if isVerifying {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Text("Verify & Save")
                            }
                        }
                        .disabled(isVerifying || state.sessionKey.isEmpty)
                        
                        if !state.sessionKey.isEmpty {
                            Button(action: {
                                state.sessionKey = ""
                                state.orgUuid = ""
                                state.usageBuckets = []
                                state.saveSettings()
                                verifySuccess = nil
                                verifyError = nil
                            }) {
                                Text("Disconnect")
                            }
                        }
                        
                        if let success = verifySuccess {
                            if success {
                                HStack(spacing: 4) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                    Text("Connected successfully!")
                                        .font(.system(size: 11))
                                        .foregroundColor(.green)
                                }
                            } else {
                                HStack(spacing: 4) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.red)
                                    Text(verifyError ?? "Connection failed")
                                        .font(.system(size: 11))
                                        .foregroundColor(.red)
                                }
                            }
                        }
                    }
                    
                    Divider()
                        .padding(.vertical, 4)
                    
                    // Instructions
                    VStack(alignment: .leading, spacing: 6) {
                        Text("How to find your sessionKey:")
                            .font(.system(size: 11, weight: .bold))
                        
                        Text("1. Sign in to [claude.ai](https://claude.ai) in your browser.")
                            .font(.system(size: 10))
                        Text("2. Open Developer Tools (F12 or Cmd+Option+I).")
                            .font(.system(size: 10))
                        Text("3. Go to the Application tab (Chrome/Arc/Brave) or Storage (Firefox/Safari).")
                            .font(.system(size: 10))
                        Text("4. Look for Cookies > https://claude.ai and copy the value of the `sessionKey` cookie (starts with `sk-ant-sid01-`).")
                            .font(.system(size: 10))
                    }
                    .foregroundColor(.secondary)
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Claude Code CLI Integration")
                        .font(.system(size: 13, weight: .semibold))
                    
                    Text("Reads the active OAuth session key established by the Claude Code CLI (`claude login`).")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 12) {
                        Button(action: scanCLIKeychain) {
                            HStack(spacing: 6) {
                                Image(systemName: "key.viewfinder")
                                Text("Scan Keychain for Claude Code")
                            }
                        }
                        
                        if state.selectedMethod == "cli" && verifySuccess == true {
                            Button(action: {
                                state.selectedMethod = "web"
                                state.usageBuckets = []
                                state.saveSettings()
                                verifySuccess = nil
                                verifyError = nil
                            }) {
                                Text("Disconnect")
                            }
                        }
                    }
                    
                    if let success = verifySuccess {
                        if success {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 4) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                    Text("Found active Claude Code session!")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(.green)
                                }
                                Text("Ready to track API OAuth session usage.")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                            .padding(8)
                            .background(Color.green.opacity(0.1))
                            .cornerRadius(6)
                        } else {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 4) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.red)
                                    Text("Authentication scan failed")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(.red)
                                }
                                Text(verifyError ?? "No credentials found. Ensure you have run 'claude login' in your terminal.")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                            .padding(8)
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(6)
                        }
                    }
                }
            }
        }
    }
    
    private func verifyAndSaveWebSession() {
        isVerifying = true
        verifySuccess = nil
        verifyError = nil
        
        // Cache sessionKey locally and attempt verification
        let currentKey = state.sessionKey.trimmingCharacters(in: .whitespacesAndNewlines)
        
        state.sessionKey = currentKey
        state.selectedMethod = "web"
        state.orgUuid = "" // Clear organization cached UUID to force refetch
        
        state.refreshUsage {
            DispatchQueue.main.async {
                self.isVerifying = false
                if let error = state.errorMessage {
                    self.verifySuccess = false
                    self.verifyError = error
                } else {
                    self.verifySuccess = true
                    state.saveSettings()
                }
            }
        }
    }
    
    private func scanCLIKeychain() {
        verifySuccess = nil
        verifyError = nil
        
        if let _ = KeychainHelper.scanClaudeCodeCredentials() {
            state.selectedMethod = "cli"
            state.refreshUsage {
                DispatchQueue.main.async {
                    if let error = state.errorMessage {
                        self.verifySuccess = false
                        self.verifyError = error
                    } else {
                        self.verifySuccess = true
                        state.saveSettings()
                    }
                }
            }
        } else {
            verifySuccess = false
            verifyError = "Could not find Claude Code credentials in your macOS Keychain. Please verify you've run 'claude login' in terminal."
        }
    }
}

// MARK: - Display Tab (NEW)

struct DisplayTabView: View {
    @ObservedObject var state: AppState
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Menu Bar Display")
                .font(.system(size: 18, weight: .bold))
            
            // Display Mode
            VStack(alignment: .leading, spacing: 8) {
                Text("Display Mode")
                    .font(.system(size: 12, weight: .bold))
                
                Picker("Mode", selection: $state.displayMode) {
                    HStack(spacing: 6) {
                        Text("Stacked")
                        Text("S:22% / W:15%")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }.tag("stacked")
                    
                    HStack(spacing: 6) {
                        Text("Compact")
                        Text("S:22% W:15%")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }.tag("compact")
                    
                    HStack(spacing: 6) {
                        Text("Session Only")
                        Text("22%")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }.tag("session")
                    
                    HStack(spacing: 6) {
                        Text("Icon Only")
                        Text("C")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundColor(.secondary)
                    }.tag("icon_only")
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                .onChange(of: state.displayMode) { _ in
                    state.saveSettings()
                    NotificationCenter.default.post(name: Notification.Name("UpdateMenuBarText"), object: nil)
                }
                
                Text("Stacked mode shows session (S) and weekly (W) limits on two lines, like Macs Fan Control.")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            
            Divider()
            
            // Icon Toggle
            VStack(alignment: .leading, spacing: 6) {
                Toggle("Show \"C\" icon in menu bar", isOn: $state.showMenuBarIcon)
                    .font(.system(size: 12, weight: .bold))
                
                Text("Displays a small C letter next to the usage text for easy identification.")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .onChange(of: state.showMenuBarIcon) { _ in
                state.saveSettings()
                NotificationCenter.default.post(name: Notification.Name("UpdateMenuBarText"), object: nil)
            }
            
            Divider()
            
            // Preview
            VStack(alignment: .leading, spacing: 6) {
                Text("Preview")
                    .font(.system(size: 12, weight: .bold))
                
                HStack(spacing: 8) {
                    if state.showMenuBarIcon {
                        Text("C")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundColor(.secondary)
                    }
                    
                    switch state.displayMode {
                    case "stacked":
                        VStack(alignment: .leading, spacing: 0) {
                            Text("S:22%")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                            Text("W:15%")
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    case "compact":
                        Text("S:22% W:15%")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    case "session":
                        Text("22%")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                    case "icon_only":
                        Text("(icon only)")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    default:
                        Text("--")
                    }
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(NSColor.controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
            }
        }
    }
}

// MARK: - Settings Tab

struct SettingsTabView: View {
    @ObservedObject var state: AppState
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Preferences")
                .font(.system(size: 18, weight: .bold))
            
            // Polling Slider
            VStack(alignment: .leading, spacing: 6) {
                Text("Refresh Interval")
                    .font(.system(size: 12, weight: .bold))
                
                HStack {
                    Slider(value: $state.pollingInterval, in: 60...1800, step: 60)
                    Text("\(Int(state.pollingInterval / 60)) min")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 50, alignment: .trailing)
                }
                
                Text("Aggressive polling might trigger 429 rate limit issues. 5 minutes or more is recommended.")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .onChange(of: state.pollingInterval) { _ in
                state.saveSettings()
                NotificationCenter.default.post(name: Notification.Name("ResetPollingTimer"), object: nil)
            }
            
            Divider()
            
            // Notifications Toggle & Slider
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Enable Notifications", isOn: $state.enableNotifications)
                    .font(.system(size: 12, weight: .bold))
                
                if state.enableNotifications {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Alert Threshold")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(Int(state.thresholdNotification))%")
                                .font(.system(size: 11, weight: .bold))
                        }
                        
                        Slider(value: $state.thresholdNotification, in: 50...95, step: 5)
                        
                        Text("Sends a macOS system notification when any limit window exceeds this threshold.")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    .padding(.leading, 20)
                }
            }
            .onChange(of: state.enableNotifications) { _ in state.saveSettings() }
            .onChange(of: state.thresholdNotification) { _ in state.saveSettings() }
        }
    }
}
