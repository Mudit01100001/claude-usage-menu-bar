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
                .padding(.horizontal, 12)
                .padding(.top, 14)
                .padding(.bottom, 16)
                
                // Sidebar Buttons
                SidebarButton(title: "Dashboard", icon: "square.grid.2x2.fill", isSelected: selectedTab == "dashboard") {
                    selectedTab = "dashboard"
                }
                
                SidebarButton(title: "Connection", icon: "link", isSelected: selectedTab == "connection") {
                    selectedTab = "connection"
                }
                
                SidebarButton(title: "Menu Bar", icon: "menubar.rectangle", isSelected: selectedTab == "menuBar") {
                    selectedTab = "menuBar"
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
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
            .frame(minWidth: 140, idealWidth: 160, maxWidth: 220)
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
                    case "menuBar":
                        MenuBarTabView(state: state)
                    case "settings":
                        SettingsTabView(state: state)
                    default:
                        EmptyView()
                    }
                }
                .padding(24)
            }
            .frame(minWidth: 380, idealWidth: 460, maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(NSColor.underPageBackgroundColor))
        }
        .frame(minWidth: 620, maxWidth: .infinity, minHeight: 450, maxHeight: .infinity)
    }
}

// MARK: - Sidebar Button

struct SidebarButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .frame(width: 16, alignment: .center)
                Text(title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.orange.opacity(0.18) : (isHovered ? Color.primary.opacity(0.06) : Color.clear))
            )
            .foregroundColor(isSelected ? .orange : .primary)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Dashboard Tab

struct DashboardTabView: View {
    @ObservedObject var state: AppState
    
    var activeProvidersCount: Int {
        var count = 1 // Claude is always active
        if state.chatgptEnabled { count += 1 }
        if state.geminiEnabled { count += 1 }
        if state.perplexityEnabled { count += 1 }
        if state.antigravityEnabled { count += 1 }
        return count
    }
    
    var averageUtilization: Double {
        guard !state.usageBuckets.isEmpty else { return 0.0 }
        let total = state.usageBuckets.reduce(0.0) { $0 + $1.utilization }
        return total / Double(state.usageBuckets.count)
    }
    
    var totalCostEstimate: Double {
        var cost = 0.0
        if state.chatgptEnabled {
            cost += state.chatgptCurrentUsage
        }
        if state.perplexityEnabled {
            cost += state.perplexityCurrentUsage
        }
        if let claudeExtra = state.usageBuckets.first(where: { $0.name == "extra_usage" }) {
            let components = claudeExtra.resetsAt.components(separatedBy: "/")
            if let first = components.first, let val = Double(first.replacingOccurrences(of: "$", with: "")) {
                cost += val
            }
        }
        return cost
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Usage Dashboard")
                .font(.system(size: 18, weight: .bold))
            
            // Summary Cards Row
            HStack(spacing: 12) {
                SummaryMiniCard(title: "Active Sources", value: "\(activeProvidersCount)", icon: "sparkles", color: .blue)
                SummaryMiniCard(title: "Avg Utilization", value: "\(Int(averageUtilization))%", icon: "chart.bar.fill", color: .orange)
                SummaryMiniCard(title: "Est. Total Cost", value: String(format: "$%.2f", totalCostEstimate), icon: "dollarsign.circle.fill", color: .green)
            }
            .padding(.bottom, 4)
            
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

struct SummaryMiniCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 28, height: 28)
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(color)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.primary)
            }
            Spacer()
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.4))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.08), lineWidth: 1)
        )
    }
}

struct BucketCard: View {
    let bucket: AppState.UsageBucket
    
    var brandColor: Color {
        if bucket.name.hasPrefix("chatgpt") {
            return Color(red: 16/255, green: 163/255, blue: 127/255)
        } else if bucket.name.hasPrefix("gemini") {
            return Color(red: 26/255, green: 115/255, blue: 232/255)
        } else if bucket.name.hasPrefix("perplexity") {
            return Color(red: 25/255, green: 161/255, blue: 183/255)
        } else if bucket.name.hasPrefix("antigravity") {
            return Color(red: 142/255, green: 68/255, blue: 173/255)
        } else {
            return Color.orange
        }
    }
    
    var color: Color {
        if bucket.utilization >= 90 {
            return .red
        } else if bucket.utilization >= 75 {
            return .orange
        } else {
            return brandColor
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
                        .foregroundColor(brandColor)
                    
                    Circle()
                        .trim(from: 0.0, to: CGFloat(min(bucket.utilization / 100.0, 1.0)))
                        .stroke(style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
                        .foregroundColor(color)
                        .rotationEffect(Angle(degrees: -90))
                    
                    Text("\(Int(bucket.utilization))%")
                        .font(.system(size: 12, weight: .bold))
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
    
    @State private var activeProviderTab: String = "claude"
    @State private var showClaudeSessionKey: Bool = false
    @State private var showChatGPTKey: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Connection Setup")
                .font(.system(size: 18, weight: .bold))
            
            // Sub-selector for providers
            Picker("Provider", selection: $activeProviderTab) {
                Text("Claude").tag("claude")
                Text("ChatGPT").tag("chatgpt")
                Text("Gemini").tag("gemini")
                Text("Perplexity").tag("perplexity")
                Text("Antigravity").tag("antigravity")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: activeProviderTab) { _ in
                verifySuccess = nil
                verifyError = nil
            }
            
            VStack(alignment: .leading, spacing: 14) {
                switch activeProviderTab {
                case "claude":
                    claudeSetupView
                case "chatgpt":
                    chatgptSetupView
                case "gemini":
                    geminiSetupView
                case "perplexity":
                    perplexitySetupView
                case "antigravity":
                    antigravitySetupView
                default:
                    EmptyView()
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(NSColor.controlBackgroundColor).opacity(0.3))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.08), lineWidth: 1)
            )

            // Browser-extension bridge status (feeds web-session usage via 127.0.0.1:53076)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "puzzlepiece.extension.fill")
                        .foregroundColor(.secondary)
                    Text("Browser Extension Bridge")
                        .font(.system(size: 13, weight: .bold))
                    HelpButton(
                        title: "Browser Extension Bridge",
                        content: "Some platforms only show usage inside their website. The companion browser extension reads usage from your logged-in tabs and POSTs it to this app at 127.0.0.1:53076. Load it from the claude-usage-extension-main folder via chrome://extensions (Developer mode → Load unpacked). Note: ChatGPT does not expose remaining-message counts even internally, and Antigravity is tracked locally instead."
                    )
                    Spacer()
                }
                HStack(spacing: 6) {
                    Circle()
                        .fill(state.lastExtensionIngest == nil ? Color.secondary.opacity(0.4) : Color.green)
                        .frame(width: 8, height: 8)
                    if let ts = state.lastExtensionIngest {
                        Text("Last data received \(ts.formatted(date: .omitted, time: .shortened))")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    } else {
                        Text("No extension data received yet")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(NSColor.controlBackgroundColor).opacity(0.3))
            )
        }
    }

    // MARK: - Setup Sub-Views
    
    @ViewBuilder private var claudeSetupView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Claude Tracking (Anthropic)")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.orange)
            
            HStack(spacing: 8) {
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
                
                HelpButton(
                    title: "Claude Connection Methods",
                    content: "• **Web Session**: Uses your browser's sessionKey cookie to poll Anthropic's private web app endpoint. Free but requires periodic session refresh.\n• **Code CLI**: Reads the OAuth session established by Anthropic's 'claude login' CLI tool."
                )
            }
            
            if state.selectedMethod == "web" {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Paste your Claude web sessionKey cookie below:")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 8) {
                        if showClaudeSessionKey {
                            TextField("sk-ant-sid01-...", text: $state.sessionKey)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 11, design: .monospaced))
                        } else {
                            SecureField("sk-ant-sid01-...", text: $state.sessionKey)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 11, design: .monospaced))
                        }
                        Button(action: { showClaudeSessionKey.toggle() }) {
                            Image(systemName: showClaudeSessionKey ? "eye.slash" : "eye")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    
                    HStack(spacing: 12) {
                        Button(action: verifyAndSaveWebSession) {
                            if isVerifying {
                                ProgressView().controlSize(.small)
                            } else {
                                Text("Verify & Save")
                            }
                        }
                        .disabled(isVerifying || state.sessionKey.isEmpty)
                        
                        if !state.sessionKey.isEmpty {
                            Button(action: {
                                state.sessionKey = ""
                                state.orgUuid = ""
                                state.saveSettings()
                                verifySuccess = nil
                                verifyError = nil
                                state.refreshUsage()
                            }) {
                                Text("Disconnect")
                            }
                        }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Reads the active OAuth session established by the Claude Code CLI (`claude login`).")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    
                    Button(action: scanCLIKeychain) {
                        HStack(spacing: 6) {
                            Image(systemName: "key.viewfinder")
                            Text("Scan Keychain for Claude Code")
                        }
                    }
                }
            }
            
            statusIndicatorView
        }
    }
    
    @ViewBuilder private var chatgptSetupView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ChatGPT API Tracking (OpenAI)")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(Color(red: 16/255, green: 163/255, blue: 127/255))

            Text("Tracks developer API spend ($) — not ChatGPT Plus message limits.")
                .font(.system(size: 10))
                .foregroundColor(.secondary)

            HStack(spacing: 8) {
                Picker("Method", selection: $state.chatgptMethod) {
                    Text("API spend (Admin key)").tag("api_key")
                    Text("Manual estimate").tag("simulated")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .onChange(of: state.chatgptMethod) { _ in
                    state.saveSettings()
                    state.refreshUsage()
                }
                
                HelpButton(
                    title: "ChatGPT tracking modes",
                    content: "There is no public API for ChatGPT Plus/Pro subscription usage (the message caps). The options below track different things:\n\n• API spend (Admin key): reads your OpenAI developer API cost ($) for the last 30 days via the Costs API. Needs an Admin key (sk-admin-...), not a normal sk- key.\n• Manual estimate: a number you maintain yourself; no network calls."
                )
            }
            
            if state.chatgptMethod == "api_key" {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Paste an OpenAI Admin key (`sk-admin-...`):")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                    HStack(spacing: 8) {
                        if showChatGPTKey {
                            TextField("sk-admin-...", text: $state.chatgptApiKey)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 11, design: .monospaced))
                        } else {
                            SecureField("sk-admin-...", text: $state.chatgptApiKey)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 11, design: .monospaced))
                        }
                        Button(action: { showChatGPTKey.toggle() }) {
                            Image(systemName: showChatGPTKey ? "eye.slash" : "eye")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Budget limit ($, 30d)")
                                .font(.system(size: 11))
                            Spacer()
                            Text(String(format: "$%.2f", state.chatgptMonthlyLimit))
                                .font(.system(size: 11, weight: .bold))
                        }
                        Slider(value: $state.chatgptMonthlyLimit, in: 1...100, step: 1)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Monthly budget (manual)")
                                .font(.system(size: 11))
                            Spacer()
                            Text(String(format: "$%.2f", state.chatgptMonthlyLimit))
                                .font(.system(size: 11, weight: .bold))
                        }
                        Slider(value: $state.chatgptMonthlyLimit, in: 5...100, step: 5)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Current usage (manual)")
                                .font(.system(size: 11))
                            Spacer()
                            Text(String(format: "$%.2f", state.chatgptCurrentUsage))
                                .font(.system(size: 11, weight: .bold))
                        }
                        Slider(value: $state.chatgptCurrentUsage, in: 0...state.chatgptMonthlyLimit, step: 0.25)
                    }
                }
            }
            
            Button("Save & Apply") {
                state.saveSettings()
                state.refreshUsage()
                verifySuccess = true
            }
            
            statusIndicatorView
        }
    }
    
    @ViewBuilder private var geminiSetupView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Gemini (Google) — Manual estimate")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(Color(red: 26/255, green: 115/255, blue: 232/255))

            HStack(spacing: 8) {
                Text("Google exposes no consumer Gemini usage API — this is a manual estimate.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                HelpButton(
                    title: "Why is Gemini manual?",
                    content: "Consumer Gemini (Advanced / free tier) usage is not available through any public API — quota lives in Google Cloud Console, not as a live usage feed. So this tile is a manual estimate you maintain yourself. For live numbers, use the browser-extension bridge on a logged-in Gemini tab (best effort)."
                )
            }

            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Daily request target")
                            .font(.system(size: 11))
                        Spacer()
                        Text("\(Int(state.geminiDailyLimit)) requests")
                            .font(.system(size: 11, weight: .bold))
                    }
                    Slider(value: $state.geminiDailyLimit, in: 500...5000, step: 100)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Current requests (manual)")
                            .font(.system(size: 11))
                        Spacer()
                        Text("\(Int(state.geminiCurrentUsage)) requests")
                            .font(.system(size: 11, weight: .bold))
                    }
                    Slider(value: $state.geminiCurrentUsage, in: 0...state.geminiDailyLimit, step: 50)
                }
            }

            Button("Save & Apply") {
                state.saveSettings()
                state.refreshUsage()
                verifySuccess = true
            }
            
            statusIndicatorView
        }
    }
    
    @ViewBuilder private var perplexitySetupView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Perplexity — Manual estimate")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(Color(red: 25/255, green: 161/255, blue: 183/255))

            HStack(spacing: 8) {
                Text("Perplexity usage and credits are dashboard-only — this is a manual estimate.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                HelpButton(
                    title: "Why is Perplexity manual?",
                    content: "Perplexity Pro subscription usage and API credit balance are only visible in the Perplexity dashboard — there is no public endpoint to read them programmatically. So this tile is a manual estimate you maintain yourself."
                )
            }

            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Credit balance target")
                            .font(.system(size: 11))
                        Spacer()
                        Text(String(format: "$%.2f", state.perplexityLimit))
                            .font(.system(size: 11, weight: .bold))
                    }
                    Slider(value: $state.perplexityLimit, in: 5...50, step: 5)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Credits used (manual)")
                            .font(.system(size: 11))
                        Spacer()
                        Text(String(format: "$%.2f", state.perplexityCurrentUsage))
                            .font(.system(size: 11, weight: .bold))
                    }
                    Slider(value: $state.perplexityCurrentUsage, in: 0...state.perplexityLimit, step: 0.5)
                }
            }

            Button("Save & Apply") {
                state.saveSettings()
                state.refreshUsage()
                verifySuccess = true
            }
            
            statusIndicatorView
        }
    }
    
    @ViewBuilder private var antigravitySetupView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Antigravity Log Scanner")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(Color(red: 142/255, green: 68/255, blue: 173/255))
            
            HStack(spacing: 8) {
                Picker("Method", selection: $state.antigravityMethod) {
                    Text("Live Log Scanner").tag("local_tracker")
                    Text("Manual estimate").tag("simulated")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .onChange(of: state.antigravityMethod) { _ in
                    state.saveSettings()
                    state.refreshUsage()
                }
                
                HelpButton(
                    title: "Antigravity tracking modes",
                    content: "Antigravity writes local logs, so this is real local activity — but it has no vendor-enforced cap, so the limit below is a target you choose (for the progress bar), not a hard limit.\n\n• Live Log Scanner: counts USER_INPUT lines in transcripts under ~/.gemini/antigravity/brain/.\n• Manual estimate: a number you maintain yourself."
                )
            }
            
            if state.antigravityMethod == "local_tracker" {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Tracks active agent conversation logs located in:")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    
                    Text("~/.gemini/antigravity/brain/")
                        .font(.system(size: 10, design: .monospaced))
                        .padding(6)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(4)
                    
                    HStack {
                        Text("Current Live Queries:")
                            .font(.system(size: 11))
                        Text("\(Int(state.antigravityCurrentUsage))")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.purple)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Target queries")
                                .font(.system(size: 11))
                            Spacer()
                            Text("\(Int(state.antigravityLimit)) queries")
                                .font(.system(size: 11, weight: .bold))
                        }
                        Slider(value: $state.antigravityLimit, in: 20...500, step: 10)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Current queries (manual)")
                                .font(.system(size: 11))
                            Spacer()
                            Text("\(Int(state.antigravityCurrentUsage)) queries")
                                .font(.system(size: 11, weight: .bold))
                        }
                        Slider(value: $state.antigravityCurrentUsage, in: 0...state.antigravityLimit, step: 5)
                    }
                }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Weekly target (queries)")
                        .font(.system(size: 11))
                    Spacer()
                    Text("\(Int(state.antigravityLimit)) queries")
                        .font(.system(size: 11, weight: .bold))
                }
                Slider(value: $state.antigravityLimit, in: 10...500, step: 10)
            }
            
            Button("Save & Apply") {
                state.saveSettings()
                state.refreshUsage()
                verifySuccess = true
            }
            
            statusIndicatorView
        }
    }
    
    @ViewBuilder private var statusIndicatorView: some View {
        Group {
            if let success = verifySuccess {
                if success {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Updated and verified successfully!")
                            .font(.system(size: 11))
                            .foregroundColor(.green)
                    }
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.red)
                        Text(verifyError ?? "Failed verification")
                            .font(.system(size: 11))
                            .foregroundColor(.red)
                    }
                }
            }
        }
    }
    
    private func verifyAndSaveWebSession() {
        isVerifying = true
        verifySuccess = nil
        verifyError = nil
        
        let currentKey = state.sessionKey.trimmingCharacters(in: .whitespacesAndNewlines)
        state.sessionKey = currentKey
        state.selectedMethod = "web"
        state.orgUuid = ""
        
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
            verifyError = "Could not find Claude Code credentials in Keychain."
        }
    }
}

// MARK: - Display Tab (NEW)

// MARK: - Menu Bar Tab

struct MenuBarTabView: View {
    @ObservedObject var state: AppState
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Menu Bar Settings")
                .font(.system(size: 18, weight: .bold))
            
            // Section 1: Visibility & Enablement
            VStack(alignment: .leading, spacing: 10) {
                Text("Enable Providers")
                    .font(.system(size: 13, weight: .bold))
                Text("Toggle which models are tracked. Enabled providers will show up on the Dashboard and Menu Bar dropdown.")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Enable ChatGPT (OpenAI)", isOn: $state.chatgptEnabled)
                    Toggle("Enable Gemini (Google)", isOn: $state.geminiEnabled)
                    Toggle("Enable Perplexity", isOn: $state.perplexityEnabled)
                    Toggle("Enable Antigravity Agent", isOn: $state.antigravityEnabled)
                }
                .toggleStyle(.checkbox)
                .font(.system(size: 11))
                .onChange(of: state.chatgptEnabled) { _ in state.saveSettings(); state.refreshUsage() }
                .onChange(of: state.geminiEnabled) { _ in state.saveSettings(); state.refreshUsage() }
                .onChange(of: state.perplexityEnabled) { _ in state.saveSettings(); state.refreshUsage() }
                .onChange(of: state.antigravityEnabled) { _ in state.saveSettings(); state.refreshUsage() }
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
            )
            
            // Section 2: Reordering
            VStack(alignment: .leading, spacing: 10) {
                Text("Provider Display Order")
                    .font(.system(size: 13, weight: .bold))
                Text("Move providers to adjust their priority and ordering in the Dashboard and Menu Bar dropdown.")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                
                VStack(spacing: 6) {
                    ForEach(0..<state.providerOrder.count, id: \.self) { index in
                        let provider = state.providerOrder[index]
                        let displayName = providerDisplayName(provider)
                        let isEnabled = isProviderEnabled(provider)
                        
                        HStack {
                            Image(systemName: providerIconName(provider))
                                .foregroundColor(providerColor(provider))
                                .font(.system(size: 12))
                                .frame(width: 20)
                            
                            Text(displayName)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(isEnabled ? .primary : .secondary)
                            
                            if !isEnabled {
                                Text("(Disabled)")
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            HStack(spacing: 4) {
                                Button(action: { state.moveProviderUp(provider) }) {
                                    Image(systemName: "chevron.up")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.primary)
                                }
                                .buttonStyle(.plain)
                                .frame(width: 20, height: 20)
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(4)
                                .disabled(index == 0)
                                
                                Button(action: { state.moveProviderDown(provider) }) {
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.primary)
                                }
                                .buttonStyle(.plain)
                                .frame(width: 20, height: 20)
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(4)
                                .disabled(index == state.providerOrder.count - 1)
                            }
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(NSColor.windowBackgroundColor).opacity(0.5))
                        )
                    }
                }
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
            )
            
            // Section 3: Primary Provider Selector
            VStack(alignment: .leading, spacing: 8) {
                Text("Primary Display Pinned Provider")
                    .font(.system(size: 13, weight: .bold))
                
                Picker("Primary Provider", selection: $state.primaryProvider) {
                    Text("Claude").tag("claude")
                    Text("ChatGPT").tag("chatgpt")
                    Text("Gemini").tag("gemini")
                    Text("Perplexity").tag("perplexity")
                    Text("Antigravity").tag("antigravity")
                    Text("All (Hybrid / Cycle)").tag("all")
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .onChange(of: state.primaryProvider) { _ in
                    state.saveSettings()
                    state.refreshUsage()
                    NotificationCenter.default.post(name: Notification.Name("UpdateMenuBarText"), object: nil)
                }
                
                Text("Determines which provider's metrics are shown directly in the menu bar text and widget widget.")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
            )
            
            // Section 4: Display Mode & Preview
            VStack(alignment: .leading, spacing: 12) {
                Text("Menu Bar Visual Appearance")
                    .font(.system(size: 13, weight: .bold))
                
                Picker("Display Mode", selection: $state.displayMode) {
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
                
                Toggle("Show character icon next to text", isOn: $state.showMenuBarIcon)
                    .font(.system(size: 11))
                    .onChange(of: state.showMenuBarIcon) { _ in
                        state.saveSettings()
                        NotificationCenter.default.post(name: Notification.Name("UpdateMenuBarText"), object: nil)
                    }
                
                Divider()
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("Menu Bar Preview")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                    
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
                            Text("(Icon Only)")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        default:
                            Text("--")
                        }
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color(NSColor.controlBackgroundColor)))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.15), lineWidth: 1))
                }
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
            )
        }
    }
    
    // MARK: - Helper Methods
    
    private func providerDisplayName(_ provider: String) -> String {
        switch provider {
        case "claude": return "Claude (Anthropic)"
        case "chatgpt": return "ChatGPT (OpenAI)"
        case "gemini": return "Gemini (Google)"
        case "perplexity": return "Perplexity"
        case "antigravity": return "Antigravity Agent"
        default: return provider.capitalized
        }
    }
    
    private func isProviderEnabled(_ provider: String) -> Bool {
        switch provider {
        case "claude": return true
        case "chatgpt": return state.chatgptEnabled
        case "gemini": return state.geminiEnabled
        case "perplexity": return state.perplexityEnabled
        case "antigravity": return state.antigravityEnabled
        default: return false
        }
    }
    
    private func providerIconName(_ provider: String) -> String {
        switch provider {
        case "claude": return "sparkles"
        case "chatgpt": return "message.fill"
        case "gemini": return "circle.grid.cross.fill"
        case "perplexity": return "magnifyingglass"
        case "antigravity": return "cpu"
        default: return "questionmark"
        }
    }
    
    private func providerColor(_ provider: String) -> Color {
        switch provider {
        case "claude": return .orange
        case "chatgpt": return Color(red: 16/255, green: 163/255, blue: 127/255)
        case "gemini": return Color(red: 26/255, green: 115/255, blue: 232/255)
        case "perplexity": return Color(red: 25/255, green: 161/255, blue: 183/255)
        case "antigravity": return Color(red: 142/255, green: 68/255, blue: 173/255)
        default: return .secondary
        }
    }
}

// MARK: - Help Popover Button

struct HelpButton: View {
    let title: String
    let content: String
    @State private var showPopover = false
    
    var body: some View {
        Button(action: { showPopover.toggle() }) {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showPopover, arrowEdge: .trailing) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.primary)
                Divider()
                Text(content)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
            }
            .padding(12)
            .frame(width: 280)
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
            
            Divider()
            
            // Launch at Login Toggle
            VStack(alignment: .leading, spacing: 6) {
                Toggle("Launch at Login", isOn: Binding(
                    get: { state.launchAtLogin },
                    set: { enabled in
                        state.toggleLaunchAtLogin(enabled: enabled)
                    }
                ))
                .font(.system(size: 12, weight: .bold))
                
                Text("Automatically start Claude Usage when you log into your Mac.")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
    }
}
