import Foundation
import Combine
import Security
import ServiceManagement
import WidgetKit
import Network

class AppState: ObservableObject {
    
    struct UsageBucket: Identifiable, Codable {
        var id: String { name }
        let name: String
        let utilization: Double
        let resetsAt: String
        // Where this number came from. Drives the honesty tag in the UI.
        // live_subscription | live_local | live_api_cost | manual | extension
        var source: String = "live"

        var displayName: String {
            switch name {
            case "five_hour":
                return "5-Hour Window"
            case "seven_day":
                return "7-Day Window"
            case "seven_day_sonnet":
                return "Sonnet 7-Day Limit"
            case "seven_day_opus":
                return "Opus 7-Day Limit"
            case "extra_usage":
                return "Extra Usage"
            default:
                return name.replacingOccurrences(of: "_", with: " ").capitalized
            }
        }
        
        var resetsAtDate: Date? {
            let dateFormatter = ISO8601DateFormatter()
            dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = dateFormatter.date(from: resetsAt) {
                return date
            }
            let simpleFormatter = ISO8601DateFormatter()
            return simpleFormatter.date(from: resetsAt)
        }
        
        var timeRemainingString: String {
            // For extra_usage, resetsAt contains dollar amount string (e.g. "$1.50/$10")
            if name == "extra_usage" {
                return resetsAt
            }
            guard let date = resetsAtDate else { return "Unknown" }
            let diff = date.timeIntervalSinceNow
            if diff <= 0 {
                return "Resets now"
            }
            
            let hours = Int(diff) / 3600
            let minutes = (Int(diff) % 3600) / 60
            
            if hours > 0 {
                if hours > 24 {
                    let days = hours / 24
                    let remainingHours = hours % 24
                    return "\(days)d \(remainingHours)h remaining"
                }
                return "\(hours)h \(minutes)m remaining"
            } else {
                return "\(minutes)m remaining"
            }
        }
    }
    
    // Settings Publisher
    @Published var selectedMethod: String = "web" // "web" or "cli"
    @Published var sessionKey: String = "" // For web session
    @Published var pollingInterval: Double = 300 // in seconds (default 5 mins)
    @Published var thresholdNotification: Double = 80 // percentage
    @Published var enableNotifications: Bool = true
    
    // New Settings Publishers for ChatGPT
    @Published var chatgptEnabled: Bool = false
    @Published var chatgptMethod: String = "simulated" // "api_key" or "simulated"
    @Published var chatgptApiKey: String = ""
    @Published var chatgptMonthlyLimit: Double = 20.0
    @Published var chatgptCurrentUsage: Double = 4.25 // Default simulated usage
    
    // New Settings Publishers for Gemini
    @Published var geminiEnabled: Bool = false
    @Published var geminiMethod: String = "simulated" // "api_key" or "simulated"
    @Published var geminiApiKey: String = ""
    @Published var geminiDailyLimit: Double = 1500.0
    @Published var geminiCurrentUsage: Double = 180.0 // Default simulated usage
    
    // New Settings Publishers for Perplexity
    @Published var perplexityEnabled: Bool = false
    @Published var perplexityMethod: String = "simulated" // "api_key" or "simulated"
    @Published var perplexityApiKey: String = ""
    @Published var perplexityLimit: Double = 10.0
    @Published var perplexityCurrentUsage: Double = 2.50 // Default simulated usage
    
    // New Settings Publishers for Antigravity
    @Published var antigravityEnabled: Bool = false
    @Published var antigravityMethod: String = "local_tracker" // "local_tracker" or "simulated"
    @Published var antigravityLimit: Double = 100.0
    @Published var antigravityCurrentUsage: Double = 15.0 // Default/live usage
    
    // Primary provider to show in menu bar
    @Published var primaryProvider: String = "claude" // "claude", "chatgpt", "gemini", "perplexity", "antigravity", "all"
    
    // Order of providers
    @Published var providerOrder: [String] = ["claude", "chatgpt", "gemini", "perplexity", "antigravity"]
    
    // Runtime Stats Publisher
    @Published var isFetching: Bool = false
    @Published var lastFetchTime: Date? = nil
    @Published var errorMessage: String? = nil
    @Published var usageBuckets: [UsageBucket] = []
    @Published var orgUuid: String = "" // Cached org uuid
    @Published var lastExtensionIngest: Date? = nil // Last time the browser extension POSTed usage
    
    // Menu Bar Display Settings
    @Published var displayMode: String = "stacked" // "stacked", "compact", "session", "icon_only"
    @Published var showMenuBarIcon: Bool = true
    @Published var launchAtLogin: Bool = false
    
    // Private bucket storage for consolidation
    private var claudeBuckets: [UsageBucket] = []
    private var chatgptBuckets: [UsageBucket] = []
    private var geminiBuckets: [UsageBucket] = []
    private var perplexityBuckets: [UsageBucket] = []
    private var antigravityBuckets: [UsageBucket] = []
    // Usage pushed in by the browser extension, keyed by provider id.
    private var extensionBuckets: [String: [UsageBucket]] = [:]

    // Keychain service keys for storing credentials securely
    private let sessionKeyKeychainKey = "com.mudit.ClaudeUsage.sessionKey"
    private let chatgptKeyKeychainKey = "com.mudit.ClaudeUsage.openaiKey"
    private let geminiKeyKeychainKey = "com.mudit.ClaudeUsage.geminiKey"
    private let perplexityKeyKeychainKey = "com.mudit.ClaudeUsage.perplexityKey"
    
    private var localServer: LocalUsageServer?
    
    init() {
        loadSettings()
        // Try to load cached buckets
        if let data = UserDefaults.standard.data(forKey: "cachedBuckets"),
           let decoded = try? JSONDecoder().decode([UsageBucket].self, from: data) {
            self.usageBuckets = decoded
        }
        
        self.localServer = LocalUsageServer(appState: self)
        self.localServer?.start()
    }
    
    func loadSettings() {
        self.selectedMethod = UserDefaults.standard.string(forKey: "selectedMethod") ?? "web"
        self.pollingInterval = UserDefaults.standard.double(forKey: "pollingInterval")
        if self.pollingInterval == 0 { self.pollingInterval = 300 }
        self.thresholdNotification = UserDefaults.standard.double(forKey: "thresholdNotification")
        if self.thresholdNotification == 0 { self.thresholdNotification = 80 }
        self.enableNotifications = UserDefaults.standard.object(forKey: "enableNotifications") as? Bool ?? true
        self.orgUuid = UserDefaults.standard.string(forKey: "orgUuid") ?? ""
        self.displayMode = UserDefaults.standard.string(forKey: "displayMode") ?? "stacked"
        self.showMenuBarIcon = UserDefaults.standard.object(forKey: "showMenuBarIcon") as? Bool ?? true
        
        self.chatgptEnabled = UserDefaults.standard.bool(forKey: "chatgptEnabled")
        self.chatgptMethod = UserDefaults.standard.string(forKey: "chatgptMethod") ?? "simulated"
        self.chatgptMonthlyLimit = UserDefaults.standard.double(forKey: "chatgptMonthlyLimit")
        if self.chatgptMonthlyLimit == 0 { self.chatgptMonthlyLimit = 20.0 }
        self.chatgptCurrentUsage = UserDefaults.standard.double(forKey: "chatgptCurrentUsage")
        if self.chatgptCurrentUsage == 0 { self.chatgptCurrentUsage = 4.25 }
        
        self.geminiEnabled = UserDefaults.standard.bool(forKey: "geminiEnabled")
        self.geminiMethod = UserDefaults.standard.string(forKey: "geminiMethod") ?? "simulated"
        self.geminiDailyLimit = UserDefaults.standard.double(forKey: "geminiDailyLimit")
        if self.geminiDailyLimit == 0 { self.geminiDailyLimit = 1500.0 }
        self.geminiCurrentUsage = UserDefaults.standard.double(forKey: "geminiCurrentUsage")
        if self.geminiCurrentUsage == 0 { self.geminiCurrentUsage = 180.0 }
        
        self.perplexityEnabled = UserDefaults.standard.bool(forKey: "perplexityEnabled")
        self.perplexityMethod = UserDefaults.standard.string(forKey: "perplexityMethod") ?? "simulated"
        self.perplexityLimit = UserDefaults.standard.double(forKey: "perplexityLimit")
        if self.perplexityLimit == 0 { self.perplexityLimit = 10.0 }
        self.perplexityCurrentUsage = UserDefaults.standard.double(forKey: "perplexityCurrentUsage")
        if self.perplexityCurrentUsage == 0 { self.perplexityCurrentUsage = 2.50 }
        
        self.antigravityEnabled = UserDefaults.standard.bool(forKey: "antigravityEnabled")
        self.antigravityMethod = UserDefaults.standard.string(forKey: "antigravityMethod") ?? "local_tracker"
        self.antigravityLimit = UserDefaults.standard.double(forKey: "antigravityLimit")
        if self.antigravityLimit == 0 { self.antigravityLimit = 100.0 }
        self.antigravityCurrentUsage = UserDefaults.standard.double(forKey: "antigravityCurrentUsage")
        if self.antigravityCurrentUsage == 0 { self.antigravityCurrentUsage = 15.0 }
        
        self.primaryProvider = UserDefaults.standard.string(forKey: "primaryProvider") ?? "claude"
        
        if let savedOrder = UserDefaults.standard.stringArray(forKey: "providerOrder") {
            let validProviders = ["claude", "chatgpt", "gemini", "perplexity", "antigravity"]
            var newOrder = savedOrder.filter { validProviders.contains($0) }
            for p in validProviders {
                if !newOrder.contains(p) {
                    newOrder.append(p)
                }
            }
            self.providerOrder = newOrder
        } else {
            self.providerOrder = ["claude", "chatgpt", "gemini", "perplexity", "antigravity"]
        }
        
        if let time = UserDefaults.standard.object(forKey: "lastFetchTime") as? Date {
            self.lastFetchTime = time
        }
        
        if #available(macOS 13.0, *) {
            self.launchAtLogin = SMAppService.mainApp.status == .enabled
        } else {
            self.launchAtLogin = UserDefaults.standard.bool(forKey: "launchAtLogin")
        }
        
        // Securely retrieve the keys from Keychain
        if let key = KeychainHelper.load(service: sessionKeyKeychainKey) {
            self.sessionKey = key
        }
        if let key = KeychainHelper.load(service: chatgptKeyKeychainKey) {
            self.chatgptApiKey = key
        }
        if let key = KeychainHelper.load(service: geminiKeyKeychainKey) {
            self.geminiApiKey = key
        }
        if let key = KeychainHelper.load(service: perplexityKeyKeychainKey) {
            self.perplexityApiKey = key
        }
    }
    
    func saveSettings() {
        UserDefaults.standard.set(selectedMethod, forKey: "selectedMethod")
        UserDefaults.standard.set(pollingInterval, forKey: "pollingInterval")
        UserDefaults.standard.set(thresholdNotification, forKey: "thresholdNotification")
        UserDefaults.standard.set(enableNotifications, forKey: "enableNotifications")
        UserDefaults.standard.set(orgUuid, forKey: "orgUuid")
        UserDefaults.standard.set(displayMode, forKey: "displayMode")
        UserDefaults.standard.set(showMenuBarIcon, forKey: "showMenuBarIcon")
        
        UserDefaults.standard.set(chatgptEnabled, forKey: "chatgptEnabled")
        UserDefaults.standard.set(chatgptMethod, forKey: "chatgptMethod")
        UserDefaults.standard.set(chatgptMonthlyLimit, forKey: "chatgptMonthlyLimit")
        UserDefaults.standard.set(chatgptCurrentUsage, forKey: "chatgptCurrentUsage")
        
        UserDefaults.standard.set(geminiEnabled, forKey: "geminiEnabled")
        UserDefaults.standard.set(geminiMethod, forKey: "geminiMethod")
        UserDefaults.standard.set(geminiDailyLimit, forKey: "geminiDailyLimit")
        UserDefaults.standard.set(geminiCurrentUsage, forKey: "geminiCurrentUsage")
        
        UserDefaults.standard.set(perplexityEnabled, forKey: "perplexityEnabled")
        UserDefaults.standard.set(perplexityMethod, forKey: "perplexityMethod")
        UserDefaults.standard.set(perplexityLimit, forKey: "perplexityLimit")
        UserDefaults.standard.set(perplexityCurrentUsage, forKey: "perplexityCurrentUsage")
        
        UserDefaults.standard.set(antigravityEnabled, forKey: "antigravityEnabled")
        UserDefaults.standard.set(antigravityMethod, forKey: "antigravityMethod")
        UserDefaults.standard.set(antigravityLimit, forKey: "antigravityLimit")
        UserDefaults.standard.set(antigravityCurrentUsage, forKey: "antigravityCurrentUsage")
        
        UserDefaults.standard.set(primaryProvider, forKey: "primaryProvider")
        UserDefaults.standard.set(providerOrder, forKey: "providerOrder")
        
        // Securely save credentials to Keychain
        if !sessionKey.isEmpty {
            KeychainHelper.save(service: sessionKeyKeychainKey, value: sessionKey)
        } else {
            KeychainHelper.delete(service: sessionKeyKeychainKey)
        }
        
        if !chatgptApiKey.isEmpty {
            KeychainHelper.save(service: chatgptKeyKeychainKey, value: chatgptApiKey)
        } else {
            KeychainHelper.delete(service: chatgptKeyKeychainKey)
        }
        
        if !geminiApiKey.isEmpty {
            KeychainHelper.save(service: geminiKeyKeychainKey, value: geminiApiKey)
        } else {
            KeychainHelper.delete(service: geminiKeyKeychainKey)
        }
        
        if !perplexityApiKey.isEmpty {
            KeychainHelper.save(service: perplexityKeyKeychainKey, value: perplexityApiKey)
        } else {
            KeychainHelper.delete(service: perplexityKeyKeychainKey)
        }
    }
    
    // Core function to refresh usage based on chosen method
    // Core function to refresh usage across all active providers
    func refreshUsage(completion: (() -> Void)? = nil) {
        DispatchQueue.main.async {
            self.isFetching = true
            self.errorMessage = nil
        }
        
        let group = DispatchGroup()
        
        // --- 1. CLAUDE ---
        group.enter()
        refreshClaudeUsage {
            group.leave()
        }
        
        // --- 2. CHATGPT ---
        if chatgptEnabled {
            group.enter()
            refreshChatGPTUsage {
                group.leave()
            }
        }
        
        // --- 3. GEMINI ---
        if geminiEnabled {
            group.enter()
            refreshGeminiUsage {
                group.leave()
            }
        }
        
        // --- 4. PERPLEXITY ---
        if perplexityEnabled {
            group.enter()
            refreshPerplexityUsage {
                group.leave()
            }
        }
        
        // --- 5. ANTIGRAVITY ---
        if antigravityEnabled {
            group.enter()
            refreshAntigravityUsage {
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            self.consolidateBuckets()
            self.isFetching = false
            completion?()
        }
    }
    
    private func updateStateWithError(_ errorMsg: String) {
        DispatchQueue.main.async {
            self.isFetching = false
            self.errorMessage = errorMsg
        }
    }
    
    private func parseAccessToken(from jsonStr: String) -> String? {
        struct ClaudeCodeCredentialsJSON: Codable {
            struct ClaudeAiOauth: Codable {
                let accessToken: String
            }
            let claudeAiOauth: ClaudeAiOauth
        }
        
        guard let data = jsonStr.data(using: .utf8) else { return nil }
        do {
            let parsed = try JSONDecoder().decode(ClaudeCodeCredentialsJSON.self, from: data)
            return parsed.claudeAiOauth.accessToken
        } catch {
            struct DirectTokenJSON: Codable {
                let accessToken: String
            }
            if let parsedDirect = try? JSONDecoder().decode(DirectTokenJSON.self, from: data) {
                return parsedDirect.accessToken
            }
            if jsonStr.count > 30 && !jsonStr.contains("{") {
                return jsonStr
            }
            return nil
        }
    }
    
    // MARK: - Claude Fetch & Parse
    
    private func refreshClaudeUsage(completion: @escaping () -> Void) {
        // Always assign claudeBuckets and call completion() on the main thread.
        // URLSession callbacks fire on a background queue; consolidateBuckets()
        // reads claudeBuckets on main (via group.notify(queue:.main)), so writing
        // off-main is a data race that can intermittently blank out Claude.
        func finish(_ buckets: [UsageBucket]) {
            DispatchQueue.main.async {
                self.claudeBuckets = buckets
                completion()
            }
        }

        if selectedMethod == "web" {
            guard !sessionKey.isEmpty else {
                finish([])
                return
            }

            if self.orgUuid.isEmpty {
                fetchWebOrgUuid(sessionKey: sessionKey) { [weak self] result in
                    guard let self = self else { completion(); return }
                    switch result {
                    case .success(let uuid):
                        DispatchQueue.main.async {
                            self.orgUuid = uuid
                            self.saveSettings()
                        }
                        self.fetchClaudeWebUsageDetails(sessionKey: sessionKey, orgUuid: uuid) { buckets in
                            finish(buckets)
                        }
                    case .failure(let error):
                        print("Failed to get organization ID: \(error.localizedDescription)")
                        let nsError = error as NSError
                        let msg = nsError.code == NSURLErrorTimedOut
                            ? "Claude request timed out — will retry on next refresh."
                            : "Couldn't reach Claude (org lookup): \(error.localizedDescription)"
                        DispatchQueue.main.async { self.errorMessage = msg }
                        finish([])
                    }
                }
            } else {
                fetchClaudeWebUsageDetails(sessionKey: sessionKey, orgUuid: self.orgUuid) { buckets in
                    finish(buckets)
                }
            }
        } else {
            guard let credentialsJSONString = KeychainHelper.scanClaudeCodeCredentials(),
                  let token = parseAccessToken(from: credentialsJSONString) else {
                DispatchQueue.main.async {
                    self.errorMessage = "No Claude Code credentials found in Keychain. Run `claude login`, then Scan again in Settings."
                }
                finish([])
                return
            }

            fetchClaudeCliUsage(token: token) { buckets in
                finish(buckets)
            }
        }
    }
    
    private func fetchWebOrgUuid(sessionKey: String, completion: @escaping (Result<String, Error>) -> Void) {
        guard let url = URL(string: "https://claude.ai/api/organizations") else {
            completion(.failure(NSError(domain: "Invalid URL", code: 0, userInfo: nil)))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15.0
        request.addValue("sessionKey=\(sessionKey)", forHTTPHeaderField: "Cookie")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(NSError(domain: "Invalid Response", code: 0, userInfo: nil)))
                return
            }
            
            guard httpResponse.statusCode == 200 else {
                completion(.failure(NSError(domain: "HTTP Error", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Server returned code \(httpResponse.statusCode)."])))
                return
            }
            
            guard let data = data else {
                completion(.failure(NSError(domain: "No Data", code: 0, userInfo: nil)))
                return
            }
            
            do {
                struct Org: Codable {
                    let uuid: String
                }
                let orgs = try JSONDecoder().decode([Org].self, from: data)
                if let firstOrg = orgs.first {
                    completion(.success(firstOrg.uuid))
                } else {
                    completion(.failure(NSError(domain: "No Org Found", code: 0, userInfo: nil)))
                }
            } catch {
                completion(.failure(error))
            }
        }
        task.resume()
    }
    
    private func fetchClaudeWebUsageDetails(sessionKey: String, orgUuid: String, completion: @escaping ([UsageBucket]) -> Void) {
        guard let url = URL(string: "https://claude.ai/api/organizations/\(orgUuid)/usage") else {
            completion([])
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15.0
        request.addValue("sessionKey=\(sessionKey)", forHTTPHeaderField: "Cookie")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        
        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { completion([]); return }
            if let error = error {
                print("Claude web details error: \(error.localizedDescription)")
                let isTimeout = (error as NSError).code == NSURLErrorTimedOut
                DispatchQueue.main.async {
                    self.errorMessage = isTimeout
                        ? "Claude request timed out — will retry on next refresh."
                        : "Claude web error: \(error.localizedDescription)"
                }
                completion([])
                return
            }
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                    DispatchQueue.main.async {
                        self.errorMessage = "Claude session key expired — paste a fresh one in Settings → Connection."
                    }
                    completion([])
                    return
                }
                guard httpResponse.statusCode == 200 else {
                    DispatchQueue.main.async {
                        self.errorMessage = "Claude server returned \(httpResponse.statusCode)."
                    }
                    completion([])
                    return
                }
            }
            guard let data = data else { completion([]); return }
            let buckets = self.parseClaudeBuckets(data: data)
            // Clear any stale error once we have a good fetch.
            if !buckets.isEmpty {
                DispatchQueue.main.async { self.errorMessage = nil }
            }
            completion(buckets)
        }
        task.resume()
    }
    
    private func fetchClaudeCliUsage(token: String, isRetry: Bool = false, completion: @escaping ([UsageBucket]) -> Void) {
        guard let url = URL(string: "https://api.anthropic.com/api/oauth/usage") else {
            completion([])
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15.0
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.addValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("claude-code/2.1.34", forHTTPHeaderField: "User-Agent")
        
        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { completion([]); return }
            
            if let error = error {
                print("Claude CLI error: \(error.localizedDescription)")
                completion([])
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                completion([])
                return
            }
            
            if httpResponse.statusCode == 401 && !isRetry {
                self.handleCliUnauthorized(attemptedToken: token) {
                    if let credentialsJSONString = KeychainHelper.scanClaudeCodeCredentials(),
                       let newToken = self.parseAccessToken(from: credentialsJSONString) {
                        self.fetchClaudeCliUsage(token: newToken, isRetry: true, completion: completion)
                    } else {
                        completion([])
                    }
                }
                return
            }
            
            guard httpResponse.statusCode == 200, let data = data else {
                completion([])
                return
            }
            
            let buckets = self.parseClaudeBuckets(data: data)
            completion(buckets)
        }
        task.resume()
    }
    
    private func handleCliUnauthorized(attemptedToken: String, completion: (() -> Void)?) {
        guard let credentialsJSONString = KeychainHelper.scanClaudeCodeCredentials() else {
            updateStateWithError("Could not find Claude Code credentials in your Keychain to refresh.")
            completion?()
            return
        }
        
        guard let currentToken = parseAccessToken(from: credentialsJSONString) else {
            updateStateWithError("Failed to parse access token from Keychain credentials.")
            completion?()
            return
        }
        
        if currentToken != attemptedToken {
            completion?()
            return
        }
        
        guard let refreshToken = parseRefreshToken(from: credentialsJSONString) else {
            updateStateWithError("Claude Code credentials do not contain a refresh token.")
            completion?()
            return
        }
        
        refreshOAuthToken(refreshToken: refreshToken, credentialsJSONString: credentialsJSONString) { result in
            switch result {
            case .success(_):
                completion?()
            case .failure(let error):
                self.updateStateWithError("Session expired and background refresh failed: \(error.localizedDescription)")
                completion?()
            }
        }
    }
    
    private func parseRefreshToken(from jsonStr: String) -> String? {
        guard let data = jsonStr.data(using: .utf8) else { return nil }
        if let dict = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
           let oauth = dict["claudeAiOauth"] as? [String: Any] {
            return oauth["refreshToken"] as? String
        }
        return nil
    }
    
    private func refreshOAuthToken(refreshToken: String, credentialsJSONString: String, completion: @escaping (Result<String, Error>) -> Void) {
        guard let url = URL(string: "https://api.anthropic.com/v1/oauth/token") else {
            completion(.failure(NSError(domain: "Invalid URL", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid OAuth token URL"])))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15.0
        request.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.addValue("claude-code/2.1.34", forHTTPHeaderField: "User-Agent")
        
        let payload = [
            "grant_type": "refresh_token",
            "client_id": "9d1c250a-e61b-44d9-88ed-5944d1962f5e",
            "refresh_token": refreshToken
        ]
        
        let bodyString = payload.map { "\($0.key)=\($0.value)" }.joined(separator: "&")
        request.httpBody = bodyString.data(using: .utf8)
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(NSError(domain: "Invalid Response", code: 0, userInfo: nil)))
                return
            }
            
            guard httpResponse.statusCode == 200 else {
                completion(.failure(NSError(domain: "HTTP Error", code: httpResponse.statusCode, userInfo: nil)))
                return
            }
            
            guard let data = data else {
                completion(.failure(NSError(domain: "No Data", code: 0, userInfo: nil)))
                return
            }
            
            do {
                guard let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                      let newAccessToken = json["access_token"] as? String,
                      let newRefreshToken = json["refresh_token"] as? String,
                      let expiresIn = json["expires_in"] as? Int else {
                    completion(.failure(NSError(domain: "Parse Error", code: 0, userInfo: nil)))
                    return
                }
                
                guard let origData = credentialsJSONString.data(using: .utf8),
                      var credsDict = try JSONSerialization.jsonObject(with: origData, options: [.mutableContainers]) as? [String: Any] else {
                    completion(.failure(NSError(domain: "Parse Error", code: 0, userInfo: nil)))
                    return
                }
                
                var oauthDict = credsDict["claudeAiOauth"] as? [String: Any] ?? [String: Any]()
                oauthDict["accessToken"] = newAccessToken
                oauthDict["refreshToken"] = newRefreshToken
                oauthDict["expiresAt"] = Int64(Date().timeIntervalSince1970 + Double(expiresIn)) * 1000
                credsDict["claudeAiOauth"] = oauthDict
                
                let updatedData = try JSONSerialization.data(withJSONObject: credsDict, options: [.prettyPrinted])
                guard let updatedStr = String(data: updatedData, encoding: .utf8) else {
                    completion(.failure(NSError(domain: "Serialization Error", code: 0, userInfo: nil)))
                    return
                }
                
                let writeSuccess = KeychainHelper.writeClaudeCodeCredentials(value: updatedStr)
                if !writeSuccess {
                    completion(.failure(NSError(domain: "Keychain Error", code: 0, userInfo: nil)))
                    return
                }
                
                completion(.success(newAccessToken))
                
            } catch {
                completion(.failure(error))
            }
        }
        task.resume()
    }
    
    private func parseClaudeBuckets(data: Data) -> [UsageBucket] {
        do {
            guard let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
                return []
            }
            var tempBuckets: [UsageBucket] = []
            
            for (key, value) in json {
                guard let val = value as? [String: Any] else { continue }
                
                if key == "extra_usage" {
                    if let isEnabled = val["is_enabled"] as? Bool, isEnabled,
                       let utilization = val["utilization"] as? Double {
                        let usedCents = val["used_credits"] as? Int ?? 0
                        let limitCents = val["monthly_limit"] as? Int ?? 0
                        let usedDollars = String(format: "$%.2f", Double(usedCents) / 100.0)
                        let limitDollars = String(format: "$%.0f", Double(limitCents) / 100.0)
                        tempBuckets.append(UsageBucket(
                            name: key,
                            utilization: utilization,
                            resetsAt: "\(usedDollars)/\(limitDollars)",
                            source: "live_subscription"
                        ))
                    }
                } else {
                    if let utilization = val["utilization"] as? Double,
                       let resetsAtStr = val["resets_at"] as? String {
                        tempBuckets.append(UsageBucket(
                            name: key,
                            utilization: utilization,
                            resetsAt: resetsAtStr,
                            source: "live_subscription"
                        ))
                    }
                }
            }
            
            tempBuckets.sort { a, b in
                let order = ["five_hour": 0, "seven_day": 1, "seven_day_sonnet": 2, "seven_day_opus": 3, "extra_usage": 99]
                return (order[a.name] ?? 50) < (order[b.name] ?? 50)
            }
            return tempBuckets
        } catch {
            print("Failed to parse Claude usage data: \(error)")
            return []
        }
    }
    
    // MARK: - ChatGPT Fetch
    
    private func refreshChatGPTUsage(completion: @escaping () -> Void) {
        // IMPORTANT: there is no public API for ChatGPT Plus/Pro *subscription* usage.
        // "api_key" mode reports your OpenAI *developer API* spend ($) via the Costs API,
        // which requires an Admin key (sk-admin-...). "simulated" is a manual estimate.
        // Neither reflects ChatGPT subscription message caps.
        func finish(_ buckets: [UsageBucket]) {
            DispatchQueue.main.async {
                self.chatgptBuckets = buckets
                completion()
            }
        }

        if chatgptMethod == "simulated" {
            let util = min((chatgptCurrentUsage / max(chatgptMonthlyLimit, 1)) * 100.0, 100.0)
            let resetsStr = String(format: "$%.2f / $%.2f (manual)", chatgptCurrentUsage, chatgptMonthlyLimit)
            finish([UsageBucket(name: "chatgpt_api", utilization: util, resetsAt: resetsStr, source: "manual")])
            return
        }

        guard !chatgptApiKey.isEmpty else {
            finish([UsageBucket(name: "chatgpt_api", utilization: 0.0, resetsAt: "Admin API key missing", source: "manual")])
            return
        }

        // OpenAI Costs API — developer API spend over the trailing ~30 days.
        let startTime = Int(Date().timeIntervalSince1970) - (30 * 24 * 3600)
        guard let url = URL(string: "https://api.openai.com/v1/organization/costs?start_time=\(startTime)&limit=31") else {
            finish([])
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15.0
        request.addValue("Bearer \(chatgptApiKey)", forHTTPHeaderField: "Authorization")

        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { completion(); return }

            if let error = error {
                print("OpenAI Costs fetch error: \(error.localizedDescription)")
                let util = min((self.chatgptCurrentUsage / max(self.chatgptMonthlyLimit, 1)) * 100.0, 100.0)
                let resetsStr = String(format: "$%.2f / $%.2f (offline)", self.chatgptCurrentUsage, self.chatgptMonthlyLimit)
                finish([UsageBucket(name: "chatgpt_api", utilization: util, resetsAt: resetsStr, source: "manual")])
                return
            }

            if let http = response as? HTTPURLResponse, http.statusCode == 401 {
                finish([UsageBucket(name: "chatgpt_api", utilization: 0.0, resetsAt: "Needs an Admin key (sk-admin-…)", source: "manual")])
                return
            }

            guard let data = data else { finish([]); return }

            struct CostsResponse: Codable {
                struct Bucket: Codable {
                    struct Result: Codable {
                        struct Amount: Codable { let value: Double? }
                        let amount: Amount?
                    }
                    let results: [Result]?
                }
                let data: [Bucket]?
            }

            do {
                let decoded = try JSONDecoder().decode(CostsResponse.self, from: data)
                var totalCost = 0.0
                for bucket in decoded.data ?? [] {
                    for result in bucket.results ?? [] {
                        totalCost += result.amount?.value ?? 0.0
                    }
                }
                DispatchQueue.main.async {
                    self.chatgptCurrentUsage = totalCost
                    self.saveSettings()
                }
                let util = min((totalCost / max(self.chatgptMonthlyLimit, 1)) * 100.0, 100.0)
                let resetsStr = String(format: "$%.2f / $%.2f API spend (30d)", totalCost, self.chatgptMonthlyLimit)
                finish([UsageBucket(name: "chatgpt_api", utilization: util, resetsAt: resetsStr, source: "live_api_cost")])
            } catch {
                let util = min((self.chatgptCurrentUsage / max(self.chatgptMonthlyLimit, 1)) * 100.0, 100.0)
                let resetsStr = String(format: "$%.2f / $%.2f (parse error)", self.chatgptCurrentUsage, self.chatgptMonthlyLimit)
                finish([UsageBucket(name: "chatgpt_api", utilization: util, resetsAt: resetsStr, source: "manual")])
            }
        }
        task.resume()
    }
    
    // MARK: - Gemini Fetch
    
    private func refreshGeminiUsage(completion: @escaping () -> Void) {
        // Google does not expose consumer Gemini (Advanced/free-tier) usage via API,
        // so this is a manual estimate the user maintains in Settings.
        let util = min((geminiCurrentUsage / max(geminiDailyLimit, 1)) * 100.0, 100.0)
        let resetsStr = String(format: "%d / %d requests (manual)", Int(geminiCurrentUsage), Int(geminiDailyLimit))
        self.geminiBuckets = [
            UsageBucket(name: "gemini_api", utilization: util, resetsAt: resetsStr, source: "manual")
        ]
        completion()
    }
    
    // MARK: - Perplexity Fetch
    
    private func refreshPerplexityUsage(completion: @escaping () -> Void) {
        // Perplexity Pro usage and API credit balance are dashboard-only (no public
        // usage endpoint), so this is a manual estimate the user maintains in Settings.
        let util = min((perplexityCurrentUsage / max(perplexityLimit, 1)) * 100.0, 100.0)
        let resetsStr = String(format: "$%.2f / $%.2f credits (manual)", perplexityCurrentUsage, perplexityLimit)
        self.perplexityBuckets = [
            UsageBucket(name: "perplexity_api", utilization: util, resetsAt: resetsStr, source: "manual")
        ]
        completion()
    }
    
    // MARK: - Antigravity Scanner
    
    private func refreshAntigravityUsage(completion: @escaping () -> Void) {
        if antigravityMethod == "simulated" {
            // Manual estimate (live local tracking not selected).
            let util = min((antigravityCurrentUsage / max(antigravityLimit, 1)) * 100.0, 100.0)
            let resetsStr = String(format: "%d queries · target %d (manual)", Int(antigravityCurrentUsage), Int(antigravityLimit))
            self.antigravityBuckets = [
                UsageBucket(name: "antigravity_usage", utilization: util, resetsAt: resetsStr, source: "manual")
            ]
            completion()
        } else {
            DispatchQueue.global(qos: .background).async { [weak self] in
                guard let self = self else { completion(); return }
                
                let fileManager = FileManager.default
                let brainDir = fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".gemini/antigravity/brain")
                
                var queryCount = 0
                var convoCount = 0
                
                if fileManager.fileExists(atPath: brainDir.path) {
                    do {
                        let contents = try fileManager.contentsOfDirectory(at: brainDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
                        for folder in contents {
                            var isDir: ObjCBool = false
                            if fileManager.fileExists(atPath: folder.path, isDirectory: &isDir), isDir.boolValue {
                                convoCount += 1
                                let logFile = folder.appendingPathComponent(".system_generated/logs/transcript.jsonl")
                                if fileManager.fileExists(atPath: logFile.path) {
                                    if let logContents = try? String(contentsOf: logFile, encoding: .utf8) {
                                        let lines = logContents.components(separatedBy: .newlines)
                                        for line in lines {
                                            if line.contains("\"type\":\"USER_INPUT\"") {
                                                queryCount += 1
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    } catch {
                        print("Error scanning Antigravity logs: \(error)")
                    }
                }
                
                let queries = Double(queryCount)
                DispatchQueue.main.async {
                    self.antigravityCurrentUsage = queries
                    self.saveSettings()

                    // Antigravity has no vendor-enforced cap, so antigravityLimit is a
                    // user-set TARGET for the progress bar, not a real limit.
                    let util = min((queries / max(self.antigravityLimit, 1)) * 100.0, 100.0)
                    let resetsStr = String(format: "%d queries · target %d (%d convos)", Int(queries), Int(self.antigravityLimit), convoCount)
                    self.antigravityBuckets = [
                        UsageBucket(name: "antigravity_usage", utilization: util, resetsAt: resetsStr, source: "live_local")
                    ]
                    completion()
                }
            }
        }
    }
    
    // MARK: - Browser-extension ingest

    /// Called by LocalUsageServer when the browser extension POSTs usage for a provider.
    func ingestExtensionUsage(provider: String, buckets: [UsageBucket]) {
        DispatchQueue.main.async {
            let tagged = buckets.map {
                UsageBucket(name: $0.name, utilization: $0.utilization, resetsAt: $0.resetsAt, source: "extension")
            }
            self.extensionBuckets[provider] = tagged
            self.lastExtensionIngest = Date()
            self.consolidateBuckets()
            NotificationCenter.default.post(name: Notification.Name("UpdateMenuBarText"), object: nil)
        }
    }

    // MARK: - State Consolidation

    /// Prefer real direct data; fall back to extension-pushed data; finally manual direct data.
    private func resolvedBuckets(direct: [UsageBucket], provider: String) -> [UsageBucket] {
        let ext = extensionBuckets[provider] ?? []
        let directIsReal = !direct.isEmpty && !direct.allSatisfy { $0.source == "manual" }
        if directIsReal { return direct }
        if !ext.isEmpty { return ext }
        return direct
    }

    private func consolidateBuckets() {
        var allBuckets: [UsageBucket] = []

        for provider in providerOrder {
            switch provider {
            case "claude":
                allBuckets.append(contentsOf: resolvedBuckets(direct: claudeBuckets, provider: "claude"))
            case "chatgpt":
                if chatgptEnabled {
                    allBuckets.append(contentsOf: resolvedBuckets(direct: chatgptBuckets, provider: "chatgpt"))
                }
            case "gemini":
                if geminiEnabled {
                    allBuckets.append(contentsOf: resolvedBuckets(direct: geminiBuckets, provider: "gemini"))
                }
            case "perplexity":
                if perplexityEnabled {
                    allBuckets.append(contentsOf: resolvedBuckets(direct: perplexityBuckets, provider: "perplexity"))
                }
            case "antigravity":
                if antigravityEnabled {
                    allBuckets.append(contentsOf: resolvedBuckets(direct: antigravityBuckets, provider: "antigravity"))
                }
            default:
                break
            }
        }
        
        self.usageBuckets = allBuckets
        self.lastFetchTime = Date()
        
        // Cache the buckets in UserDefaults
        if let encoded = try? JSONEncoder().encode(allBuckets) {
            UserDefaults.standard.set(encoded, forKey: "cachedBuckets")
        }
        UserDefaults.standard.set(self.lastFetchTime, forKey: "lastFetchTime")
        
        self.updateSharedWidgetData()
    }
    
    func moveProviderUp(_ provider: String) {
        guard let index = providerOrder.firstIndex(of: provider), index > 0 else { return }
        providerOrder.swapAt(index, index - 1)
        saveSettings()
        consolidateBuckets()
        NotificationCenter.default.post(name: Notification.Name("UpdateMenuBarText"), object: nil)
    }
    
    func moveProviderDown(_ provider: String) {
        guard let index = providerOrder.firstIndex(of: provider), index < providerOrder.count - 1 else { return }
        providerOrder.swapAt(index, index + 1)
        saveSettings()
        consolidateBuckets()
        NotificationCenter.default.post(name: Notification.Name("UpdateMenuBarText"), object: nil)
    }
    
    func toggleLaunchAtLogin(enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    if SMAppService.mainApp.status != .enabled {
                        try SMAppService.mainApp.register()
                    }
                } else {
                    if SMAppService.mainApp.status == .enabled {
                        try SMAppService.mainApp.unregister()
                    }
                }
                DispatchQueue.main.async {
                    self.launchAtLogin = enabled
                }
            } catch {
                print("Error toggling launch at login: \(error)")
            }
        } else {
            UserDefaults.standard.set(enabled, forKey: "launchAtLogin")
            DispatchQueue.main.async {
                self.launchAtLogin = enabled
            }
        }
    }
    
    func computeSharedUsageInfo() -> SharedUsageInfo {
        var sessionUtil = 0.0
        var sessionTime = "No data"
        var weeklyUtil = 0.0
        var weeklyTime = "No data"
        
        if primaryProvider == "claude" {
            let session = self.usageBuckets.first(where: { $0.name == "five_hour" })
            let weekly = self.usageBuckets.first(where: { $0.name == "seven_day" })
            sessionUtil = session?.utilization ?? 0.0
            sessionTime = session?.timeRemainingString ?? "No data"
            weeklyUtil = weekly?.utilization ?? 0.0
            weeklyTime = weekly?.timeRemainingString ?? "No data"
        } else if primaryProvider == "chatgpt" {
            let bucket = self.usageBuckets.first(where: { $0.name == "chatgpt_api" })
            sessionUtil = bucket?.utilization ?? 0.0
            sessionTime = bucket?.timeRemainingString ?? "No data"
            weeklyUtil = 0.0
            weeklyTime = "ChatGPT API"
        } else if primaryProvider == "gemini" {
            let bucket = self.usageBuckets.first(where: { $0.name == "gemini_api" })
            sessionUtil = bucket?.utilization ?? 0.0
            sessionTime = bucket?.timeRemainingString ?? "No data"
            weeklyUtil = 0.0
            weeklyTime = "Gemini API"
        } else if primaryProvider == "perplexity" {
            let bucket = self.usageBuckets.first(where: { $0.name == "perplexity_api" })
            sessionUtil = bucket?.utilization ?? 0.0
            sessionTime = bucket?.timeRemainingString ?? "No data"
            weeklyUtil = 0.0
            weeklyTime = "Perplexity API"
        } else if primaryProvider == "antigravity" {
            let bucket = self.usageBuckets.first(where: { $0.name == "antigravity_usage" })
            sessionUtil = bucket?.utilization ?? 0.0
            sessionTime = bucket?.timeRemainingString ?? "No data"
            weeklyUtil = 0.0
            weeklyTime = "Antigravity Agent"
        } else {
            let session = self.usageBuckets.first(where: { $0.name == "five_hour" })
            sessionUtil = session?.utilization ?? 0.0
            sessionTime = session?.timeRemainingString ?? "No data"
            
            if let other = self.usageBuckets.first(where: { $0.name != "five_hour" && $0.name != "seven_day" && $0.name != "extra_usage" }) {
                weeklyUtil = other.utilization
                weeklyTime = other.displayName
            } else {
                let weekly = self.usageBuckets.first(where: { $0.name == "seven_day" })
                weeklyUtil = weekly?.utilization ?? 0.0
                weeklyTime = weekly?.timeRemainingString ?? "No data"
            }
        }
        
        return SharedUsageInfo(
            sessionUtilization: sessionUtil,
            sessionTimeRemaining: sessionTime,
            weeklyUtilization: weeklyUtil,
            weeklyTimeRemaining: weeklyTime
        )
    }
    
    private func updateSharedWidgetData() {
        let info = computeSharedUsageInfo()
        
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.Mudit01100001.claude-usage") else {
            WidgetCenter.shared.reloadAllTimelines()
            return
        }
        
        try? FileManager.default.createDirectory(at: containerURL, withIntermediateDirectories: true, attributes: nil)
        
        let fileURL = containerURL.appendingPathComponent("usage.json")
        do {
            let data = try JSONEncoder().encode(info)
            try data.write(to: fileURL)
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            print("Failed to write widget data: \(error)")
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}

// MARK: - UsageBucket Codable (tolerant of older cached data written before `source` existed)

extension AppState.UsageBucket {
    enum CodingKeys: String, CodingKey { case name, utilization, resetsAt, source }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try c.decode(String.self, forKey: .name)
        self.utilization = try c.decode(Double.self, forKey: .utilization)
        self.resetsAt = try c.decode(String.self, forKey: .resetsAt)
        self.source = try c.decodeIfPresent(String.self, forKey: .source) ?? "live"
    }
}

// MARK: - Local HTTP Server for Widget (Bypasses Sandboxed App Group Team ID check)

struct SharedUsageInfo: Codable {
    let sessionUtilization: Double
    let sessionTimeRemaining: String
    let weeklyUtilization: Double
    let weeklyTimeRemaining: String
}

class LocalUsageServer {
    private var listener: NWListener?
    private unowned var appState: AppState
    
    init(appState: AppState) {
        self.appState = appState
    }
    
    func start(port: UInt16 = 53076) {
        do {
            let nwPort = NWEndpoint.Port(rawValue: port)!
            let parameters = NWParameters.tcp
            self.listener = try NWListener(using: parameters, on: nwPort)
            
            self.listener?.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    print("Local usage server ready on port \(port)")
                case .failed(let error):
                    print("Local usage server failed: \(error)")
                default:
                    break
                }
            }
            
            self.listener?.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }
            
            self.listener?.start(queue: .global(qos: .background))
        } catch {
            print("Failed to start local usage server: \(error)")
        }
    }
    
    func stop() {
        self.listener?.cancel()
        self.listener = nil
    }
    
    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .background))
        receiveRequest(connection, accumulated: Data())
    }

    // Accumulate until headers are complete and the declared body has arrived.
    // Payloads here are tiny localhost JSON, but TCP can still fragment.
    private func receiveRequest(_ connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else { connection.cancel(); return }
            if let error = error {
                print("Connection receive error: \(error)")
                connection.cancel()
                return
            }

            var buffer = accumulated
            if let data = data { buffer.append(data) }

            guard let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)) else {
                if isComplete { connection.cancel() } else { self.receiveRequest(connection, accumulated: buffer) }
                return
            }

            let headerData = buffer.subdata(in: buffer.startIndex..<headerEnd.lowerBound)
            let headerStr = String(data: headerData, encoding: .utf8) ?? ""
            let lines = headerStr.components(separatedBy: "\r\n")
            let requestLine = lines.first ?? ""
            let parts = requestLine.components(separatedBy: " ")
            let method = parts.first ?? "GET"
            let path = parts.count > 1 ? parts[1] : "/"

            var contentLength = 0
            for line in lines where line.lowercased().hasPrefix("content-length:") {
                contentLength = Int(line.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)) ?? 0
            }

            let body = buffer.subdata(in: headerEnd.upperBound..<buffer.endIndex)
            if body.count < contentLength && !isComplete {
                self.receiveRequest(connection, accumulated: buffer)
                return
            }

            self.route(connection, method: method, path: path, body: body)
        }
    }

    private func route(_ connection: NWConnection, method: String, path: String, body: Data) {
        switch method {
        case "OPTIONS":
            sendPreflight(connection)
        case "POST" where path.hasPrefix("/ingest"):
            handleIngest(connection, body: body)
        default:
            sendUsage(connection) // GET — widget data (original behavior)
        }
    }

    private func handleIngest(_ connection: NWConnection, body: Data) {
        struct IngestPayload: Codable {
            struct InBucket: Codable {
                let name: String
                let utilization: Double
                let resetsAt: String
            }
            let provider: String
            let buckets: [InBucket]
        }

        var ok = false
        if let payload = try? JSONDecoder().decode(IngestPayload.self, from: body), !payload.provider.isEmpty {
            let buckets = payload.buckets.map {
                AppState.UsageBucket(name: $0.name, utilization: $0.utilization, resetsAt: $0.resetsAt)
            }
            appState.ingestExtensionUsage(provider: payload.provider, buckets: buckets)
            ok = true
        }
        sendJSON(connection, status: ok ? "200 OK" : "400 Bad Request", json: ok ? "{\"ok\":true}" : "{\"ok\":false}")
    }

    private func sendUsage(_ connection: NWConnection) {
        let info = appState.computeSharedUsageInfo()
        guard let jsonData = try? JSONEncoder().encode(info),
              let jsonStr = String(data: jsonData, encoding: .utf8) else {
            connection.cancel()
            return
        }
        sendJSON(connection, status: "200 OK", json: jsonStr)
    }

    private func sendPreflight(_ connection: NWConnection) {
        let response = "HTTP/1.1 204 No Content\r\n"
            + "Access-Control-Allow-Origin: *\r\n"
            + "Access-Control-Allow-Methods: GET, POST, OPTIONS\r\n"
            + "Access-Control-Allow-Headers: Content-Type\r\n"
            + "Content-Length: 0\r\n"
            + "Connection: close\r\n\r\n"
        write(connection, response)
    }

    private func sendJSON(_ connection: NWConnection, status: String, json: String) {
        let jsonData = Data(json.utf8)
        let response = "HTTP/1.1 \(status)\r\n"
            + "Content-Type: application/json\r\n"
            + "Content-Length: \(jsonData.count)\r\n"
            + "Access-Control-Allow-Origin: *\r\n"
            + "Connection: close\r\n\r\n"
            + json
        write(connection, response)
    }

    private func write(_ connection: NWConnection, _ response: String) {
        guard let data = response.data(using: .utf8) else { connection.cancel(); return }
        connection.send(content: data, completion: .contentProcessed({ error in
            if let error = error { print("Connection send error: \(error)") }
            connection.cancel()
        }))
    }
}

