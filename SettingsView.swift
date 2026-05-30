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
    @State private var showGeminiKey: Bool = false
    @State private var showPerplexityKey: Bool = false
    
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
        }
    }
    
    // MARK: - Setup Sub-Views
    
    @ViewBuilder private var claudeSetupView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Claude Tracking (Anthropic)")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.orange)
            
            Picker("Method", selection: $state.selectedMethod) {
                Text("Claude Web Session").tag("web")
                Text("Claude Code CLI").tag("cli")
            }
            .pickerStyle(.segmented)
            .onChange(of: state.selectedMethod) { _ in
                verifySuccess = nil
                verifyError = nil
                state.saveSettings()
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
            HStack {
                Text("ChatGPT API Tracking (OpenAI)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Color(red: 16/255, green: 163/255, blue: 127/255))
                Spacer()
                Toggle("", isOn: $state.chatgptEnabled)
                    .toggleStyle(.switch)
                    .onChange(of: state.chatgptEnabled) { _ in
                        state.saveSettings()
                        state.refreshUsage()
                    }
            }
            
            if state.chatgptEnabled {
                Picker("Method", selection: $state.chatgptMethod) {
                    Text("OpenAI API Key").tag("api_key")
                    Text("Simulation Mode").tag("simulated")
                }
                .pickerStyle(.segmented)
                .onChange(of: state.chatgptMethod) { _ in
                    state.saveSettings()
                    state.refreshUsage()
                }
                
                if state.chatgptMethod == "api_key" {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Paste your OpenAI API Key (`sk-...`):")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        
                        HStack(spacing: 8) {
                            if showChatGPTKey {
                                TextField("sk-...", text: $state.chatgptApiKey)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 11, design: .monospaced))
                            } else {
                                SecureField("sk-...", text: $state.chatgptApiKey)
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
                                Text("Daily Cost Budget Limit")
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
                                Text("Simulated Monthly Limit")
                                    .font(.system(size: 11))
                                Spacer()
                                Text(String(format: "$%.2f", state.chatgptMonthlyLimit))
                                    .font(.system(size: 11, weight: .bold))
                            }
                            Slider(value: $state.chatgptMonthlyLimit, in: 5...100, step: 5)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Simulated Current Usage")
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
            } else {
                Text("Enable ChatGPT tracking to view usage metrics.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            
            statusIndicatorView
        }
    }
    
    @ViewBuilder private var geminiSetupView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Gemini API Quota Tracking (Google)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Color(red: 26/255, green: 115/255, blue: 232/255))
                Spacer()
                Toggle("", isOn: $state.geminiEnabled)
                    .toggleStyle(.switch)
                    .onChange(of: state.geminiEnabled) { _ in
                        state.saveSettings()
                        state.refreshUsage()
                    }
            }
            
            if state.geminiEnabled {
                Picker("Method", selection: $state.geminiMethod) {
                    Text("API Quota Tracker").tag("api_key")
                    Text("Simulation Mode").tag("simulated")
                }
                .pickerStyle(.segmented)
                .onChange(of: state.geminiMethod) { _ in
                    state.saveSettings()
                    state.refreshUsage()
                }
                
                if state.geminiMethod == "api_key" {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Enter your Gemini API Key (Quota local tracker):")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        
                        HStack(spacing: 8) {
                            if showGeminiKey {
                                TextField("AIzaSy...", text: $state.geminiApiKey)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 11, design: .monospaced))
                            } else {
                                SecureField("AIzaSy...", text: $state.geminiApiKey)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 11, design: .monospaced))
                            }
                            Button(action: { showGeminiKey.toggle() }) {
                                Image(systemName: showGeminiKey ? "eye.slash" : "eye")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Daily Limit Quota")
                                    .font(.system(size: 11))
                                Spacer()
                                Text("\(Int(state.geminiDailyLimit)) requests")
                                    .font(.system(size: 11, weight: .bold))
                            }
                            Slider(value: $state.geminiDailyLimit, in: 100...5000, step: 100)
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Simulated Limit Requests")
                                    .font(.system(size: 11))
                                Spacer()
                                Text("\(Int(state.geminiDailyLimit)) requests")
                                    .font(.system(size: 11, weight: .bold))
                            }
                            Slider(value: $state.geminiDailyLimit, in: 500...5000, step: 100)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Simulated Requests Count")
                                    .font(.system(size: 11))
                                Spacer()
                                Text("\(Int(state.geminiCurrentUsage)) requests")
                                    .font(.system(size: 11, weight: .bold))
                            }
                            Slider(value: $state.geminiCurrentUsage, in: 0...state.geminiDailyLimit, step: 50)
                        }
                    }
                }
                
                Button("Save & Apply") {
                    state.saveSettings()
                    state.refreshUsage()
                    verifySuccess = true
                }
            } else {
                Text("Enable Gemini tracking to view usage metrics.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            
            statusIndicatorView
        }
    }
    
    @ViewBuilder private var perplexitySetupView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Perplexity Pro/API Tracking")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Color(red: 25/255, green: 161/255, blue: 183/255))
                Spacer()
                Toggle("", isOn: $state.perplexityEnabled)
                    .toggleStyle(.switch)
                    .onChange(of: state.perplexityEnabled) { _ in
                        state.saveSettings()
                        state.refreshUsage()
                    }
            }
            
            if state.perplexityEnabled {
                Picker("Method", selection: $state.perplexityMethod) {
                    Text("Prepaid Balance").tag("api_key")
                    Text("Simulation Mode").tag("simulated")
                }
                .pickerStyle(.segmented)
                .onChange(of: state.perplexityMethod) { _ in
                    state.saveSettings()
                    state.refreshUsage()
                }
                
                VStack(alignment: .leading, spacing: 10) {
                    if state.perplexityMethod == "api_key" {
                        Text("Enter your Perplexity API Key:")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        
                        HStack(spacing: 8) {
                            if showPerplexityKey {
                                TextField("pplx-...", text: $state.perplexityApiKey)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 11, design: .monospaced))
                            } else {
                                SecureField("pplx-...", text: $state.perplexityApiKey)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 11, design: .monospaced))
                            }
                            Button(action: { showPerplexityKey.toggle() }) {
                                Image(systemName: showPerplexityKey ? "eye.slash" : "eye")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Prepaid Credit Balance Limit")
                                .font(.system(size: 11))
                            Spacer()
                            Text(String(format: "$%.2f", state.perplexityLimit))
                                .font(.system(size: 11, weight: .bold))
                        }
                        Slider(value: $state.perplexityLimit, in: 5...50, step: 5)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Simulated Credits Used")
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
            } else {
                Text("Enable Perplexity tracking to view usage metrics.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            
            statusIndicatorView
        }
    }
    
    @ViewBuilder private var antigravitySetupView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Antigravity Log Scanner")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Color(red: 142/255, green: 68/255, blue: 173/255))
                Spacer()
                Toggle("", isOn: $state.antigravityEnabled)
                    .toggleStyle(.switch)
                    .onChange(of: state.antigravityEnabled) { _ in
                        state.saveSettings()
                        state.refreshUsage()
                    }
            }
            
            if state.antigravityEnabled {
                Picker("Method", selection: $state.antigravityMethod) {
                    Text("Live Log Scanner").tag("local_tracker")
                    Text("Simulation Mode").tag("simulated")
                }
                .pickerStyle(.segmented)
                .onChange(of: state.antigravityMethod) { _ in
                    state.saveSettings()
                    state.refreshUsage()
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
                                Text("Simulated Queries limit")
                                    .font(.system(size: 11))
                                Spacer()
                                Text("\(Int(state.antigravityLimit)) queries")
                                    .font(.system(size: 11, weight: .bold))
                            }
                            Slider(value: $state.antigravityLimit, in: 20...500, step: 10)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Simulated Queries count")
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
                        Text("Weekly Query Limit")
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
            } else {
                Text("Enable Antigravity agent tracking to view usage metrics.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
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

struct DisplayTabView: View {
    @ObservedObject var state: AppState
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Menu Bar Display")
                .font(.system(size: 18, weight: .bold))
            
            // Primary Provider Selector
            VStack(alignment: .leading, spacing: 8) {
                Text("Primary Provider (Menu Bar & Widget)")
                    .font(.system(size: 12, weight: .bold))
                
                Picker("Primary Provider", selection: $state.primaryProvider) {
                    Text("Claude").tag("claude")
                    Text("ChatGPT").tag("chatgpt")
                    Text("Gemini").tag("gemini")
                    Text("Perplexity").tag("perplexity")
                    Text("Antigravity").tag("antigravity")
                    Text("All (Hybrid / Cycle)").tag("all")
                }
                .pickerStyle(.menu)
                .onChange(of: state.primaryProvider) { _ in
                    state.saveSettings()
                    state.refreshUsage() // Updates shared widget and menu bar immediately
                    NotificationCenter.default.post(name: Notification.Name("UpdateMenuBarText"), object: nil)
                }
                
                Text("Selects which provider's usage data is pinned to the menu bar text and desktop widget.")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            
            Divider()
            
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
