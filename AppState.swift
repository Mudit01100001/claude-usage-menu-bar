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
    
    // Runtime Stats Publisher
    @Published var isFetching: Bool = false
    @Published var lastFetchTime: Date? = nil
    @Published var errorMessage: String? = nil
    @Published var usageBuckets: [UsageBucket] = []
    @Published var orgUuid: String = "" // Cached org uuid
    
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
        if selectedMethod == "web" {
            guard !sessionKey.isEmpty else {
                self.claudeBuckets = []
                completion()
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
                            self.claudeBuckets = buckets
                            completion()
                        }
                    case .failure(let error):
                        print("Failed to get organization ID: \(error.localizedDescription)")
                        self.claudeBuckets = []
                        completion()
                    }
                }
            } else {
                fetchClaudeWebUsageDetails(sessionKey: sessionKey, orgUuid: self.orgUuid) { buckets in
                    self.claudeBuckets = buckets
                    completion()
                }
            }
        } else {
            guard let credentialsJSONString = KeychainHelper.scanClaudeCodeCredentials(),
                  let token = parseAccessToken(from: credentialsJSONString) else {
                self.claudeBuckets = []
                completion()
                return
            }
            
            fetchClaudeCliUsage(token: token) { buckets in
                self.claudeBuckets = buckets
                completion()
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
        request.timeoutInterval = 5.0
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
        request.timeoutInterval = 5.0
        request.addValue("sessionKey=\(sessionKey)", forHTTPHeaderField: "Cookie")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        
        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { completion([]); return }
            if let error = error {
                print("Claude web details error: \(error.localizedDescription)")
                completion([])
                return
            }
            guard let data = data else { completion([]); return }
            let buckets = self.parseClaudeBuckets(data: data)
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
        request.timeoutInterval = 5.0
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
        request.timeoutInterval = 5.0
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
                            resetsAt: "\(usedDollars)/\(limitDollars)"
                        ))
                    }
                } else {
                    if let utilization = val["utilization"] as? Double,
                       let resetsAtStr = val["resets_at"] as? String {
                        tempBuckets.append(UsageBucket(
                            name: key,
                            utilization: utilization,
                            resetsAt: resetsAtStr
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
        if chatgptMethod == "simulated" {
            let util = min((chatgptCurrentUsage / chatgptMonthlyLimit) * 100.0, 100.0)
            let resetsStr = String(format: "$%.2f / $%.2f monthly", chatgptCurrentUsage, chatgptMonthlyLimit)
            self.chatgptBuckets = [
                UsageBucket(name: "chatgpt_api", utilization: util, resetsAt: resetsStr)
            ]
            completion()
        } else {
            guard !chatgptApiKey.isEmpty else {
                let resetsStr = "API Key missing"
                self.chatgptBuckets = [
                    UsageBucket(name: "chatgpt_api", utilization: 0.0, resetsAt: resetsStr)
                ]
                completion()
                return
            }
            
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            let todayStr = formatter.string(from: Date())
            
            guard let url = URL(string: "https://api.openai.com/v1/usage?date=\(todayStr)") else {
                completion()
                return
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 5.0
            request.addValue("Bearer \(chatgptApiKey)", forHTTPHeaderField: "Authorization")
            
            let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
                guard let self = self else { completion(); return }
                if let error = error {
                    print("OpenAI fetch error: \(error.localizedDescription)")
                    let util = min((self.chatgptCurrentUsage / self.chatgptMonthlyLimit) * 100.0, 100.0)
                    let resetsStr = String(format: "$%.2f / $%.2f (Offline)", self.chatgptCurrentUsage, self.chatgptMonthlyLimit)
                    self.chatgptBuckets = [
                        UsageBucket(name: "chatgpt_api", utilization: util, resetsAt: resetsStr)
                    ]
                    completion()
                    return
                }
                
                guard let data = data else {
                    completion()
                    return
                }
                
                struct OpenAIUsageResponse: Codable {
                    struct UsageItem: Codable {
                        let n_context_tokens: Double?
                        let n_generated_tokens: Double?
                        let n_requests: Int?
                    }
                    let data: [UsageItem]?
                }
                
                do {
                    let decoded = try JSONDecoder().decode(OpenAIUsageResponse.self, from: data)
                    var dailyCost = 0.0
                    if let items = decoded.data {
                        for item in items {
                            let promptT = item.n_context_tokens ?? 0.0
                            let compT = item.n_generated_tokens ?? 0.0
                            dailyCost += (promptT * 0.0000025) + (compT * 0.000010)
                        }
                    }
                    
                    DispatchQueue.main.async {
                        self.chatgptCurrentUsage = dailyCost
                        self.saveSettings()
                    }
                    
                    let util = min((dailyCost / self.chatgptMonthlyLimit) * 100.0, 100.0)
                    let resetsStr = String(format: "$%.4f / $%.2f daily cost", dailyCost, self.chatgptMonthlyLimit)
                    self.chatgptBuckets = [
                        UsageBucket(name: "chatgpt_api", utilization: util, resetsAt: resetsStr)
                    ]
                    completion()
                } catch {
                    let util = min((self.chatgptCurrentUsage / self.chatgptMonthlyLimit) * 100.0, 100.0)
                    let resetsStr = String(format: "$%.2f / $%.2f (Parse error)", self.chatgptCurrentUsage, self.chatgptMonthlyLimit)
                    self.chatgptBuckets = [
                        UsageBucket(name: "chatgpt_api", utilization: util, resetsAt: resetsStr)
                    ]
                    completion()
                }
            }
            task.resume()
        }
    }
    
    // MARK: - Gemini Fetch
    
    private func refreshGeminiUsage(completion: @escaping () -> Void) {
        let util = min((geminiCurrentUsage / geminiDailyLimit) * 100.0, 100.0)
        let resetsStr = String(format: "%d / %d daily requests", Int(geminiCurrentUsage), Int(geminiDailyLimit))
        self.geminiBuckets = [
            UsageBucket(name: "gemini_api", utilization: util, resetsAt: resetsStr)
        ]
        completion()
    }
    
    // MARK: - Perplexity Fetch
    
    private func refreshPerplexityUsage(completion: @escaping () -> Void) {
        let util = min((perplexityCurrentUsage / perplexityLimit) * 100.0, 100.0)
        let resetsStr = String(format: "$%.2f / $%.2f credits", perplexityCurrentUsage, perplexityLimit)
        self.perplexityBuckets = [
            UsageBucket(name: "perplexity_api", utilization: util, resetsAt: resetsStr)
        ]
        completion()
    }
    
    // MARK: - Antigravity Scanner
    
    private func refreshAntigravityUsage(completion: @escaping () -> Void) {
        if antigravityMethod == "simulated" {
            let util = min((antigravityCurrentUsage / antigravityLimit) * 100.0, 100.0)
            let resetsStr = String(format: "%d / %d queries", Int(antigravityCurrentUsage), Int(antigravityLimit))
            self.antigravityBuckets = [
                UsageBucket(name: "antigravity_usage", utilization: util, resetsAt: resetsStr)
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
                    
                    let util = min((queries / self.antigravityLimit) * 100.0, 100.0)
                    let resetsStr = String(format: "%d / %d queries (%d convos)", Int(queries), Int(self.antigravityLimit), convoCount)
                    self.antigravityBuckets = [
                        UsageBucket(name: "antigravity_usage", utilization: util, resetsAt: resetsStr)
                    ]
                    completion()
                }
            }
        }
    }
    
    // MARK: - State Consolidation
    
    private func consolidateBuckets() {
        var allBuckets: [UsageBucket] = []
        
        allBuckets.append(contentsOf: claudeBuckets)
        
        if chatgptEnabled {
            allBuckets.append(contentsOf: chatgptBuckets)
        }
        
        if geminiEnabled {
            allBuckets.append(contentsOf: geminiBuckets)
        }
        
        if perplexityEnabled {
            allBuckets.append(contentsOf: perplexityBuckets)
        }
        
        if antigravityEnabled {
            allBuckets.append(contentsOf: antigravityBuckets)
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
        
        // Read the request data
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1024) { [weak self] data, context, isComplete, error in
            guard let self = self else { return }
            if let error = error {
                print("Connection receive error: \(error)")
                connection.cancel()
                return
            }
            
            if let data = data, let reqStr = String(data: data, encoding: .utf8), reqStr.contains("GET") {
                self.sendResponse(connection)
            } else {
                connection.cancel()
            }
        }
    }
    
    private func sendResponse(_ connection: NWConnection) {
        let info = self.appState.computeSharedUsageInfo()
        
        guard let jsonData = try? JSONEncoder().encode(info),
              let jsonStr = String(data: jsonData, encoding: .utf8) else {
            connection.cancel()
            return
        }
        
        let httpResponse = """
        HTTP/1.1 200 OK\r
        Content-Type: application/json\r
        Content-Length: \(jsonData.count)\r
        Connection: close\r
        Access-Control-Allow-Origin: *\r
        \r
        \(jsonStr)
        """
        
        guard let responseData = httpResponse.data(using: .utf8) else {
            connection.cancel()
            return
        }
        
        connection.send(content: responseData, completion: .contentProcessed({ error in
            if let error = error {
                print("Connection send error: \(error)")
            }
            connection.cancel()
        }))
    }
}

