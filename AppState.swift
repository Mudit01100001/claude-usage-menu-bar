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
    
    // Keychain service key for storing our custom Web sessionKey securely
    private let sessionKeyKeychainKey = "com.mudit.ClaudeUsage.sessionKey"
    
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
        
        if let time = UserDefaults.standard.object(forKey: "lastFetchTime") as? Date {
            self.lastFetchTime = time
        }
        
        if #available(macOS 13.0, *) {
            self.launchAtLogin = SMAppService.mainApp.status == .enabled
        } else {
            self.launchAtLogin = UserDefaults.standard.bool(forKey: "launchAtLogin")
        }
        
        // Securely retrieve the web sessionKey from Keychain
        if let key = KeychainHelper.load(service: sessionKeyKeychainKey) {
            self.sessionKey = key
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
        
        // Securely save the web sessionKey to Keychain
        if !sessionKey.isEmpty {
            KeychainHelper.save(service: sessionKeyKeychainKey, value: sessionKey)
        } else {
            KeychainHelper.delete(service: sessionKeyKeychainKey)
        }
    }
    
    // Core function to refresh usage based on chosen method
    func refreshUsage(completion: (() -> Void)? = nil) {
        DispatchQueue.main.async {
            self.isFetching = true
            self.errorMessage = nil
        }
        
        if selectedMethod == "web" {
            guard !sessionKey.isEmpty else {
                updateStateWithError("Web Session Key is not set in settings.")
                completion?()
                return
            }
            fetchWebUsage(sessionKey: sessionKey, completion: completion)
        } else {
            // CLI method: read from keychain
            guard let credentialsJSONString = KeychainHelper.scanClaudeCodeCredentials() else {
                updateStateWithError("Could not find Claude Code credentials in your Keychain. Please run 'claude login' in your terminal first.")
                completion?()
                return
            }
            
            // Parse token
            guard let token = parseAccessToken(from: credentialsJSONString) else {
                updateStateWithError("Failed to parse access token from Claude Code Keychain credentials. Try re-authenticating with 'claude login'.")
                completion?()
                return
            }
            
            fetchCliUsage(token: token, completion: completion)
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
            // Also try legacy direct format if it exists
            struct DirectTokenJSON: Codable {
                let accessToken: String
            }
            if let parsedDirect = try? JSONDecoder().decode(DirectTokenJSON.self, from: data) {
                return parsedDirect.accessToken
            }
            // If it's a raw string in the Keychain (some setups do this)
            if jsonStr.count > 30 && !jsonStr.contains("{") {
                return jsonStr
            }
            return nil
        }
    }
    
    // MARK: - Web API Fetching
    
    private func fetchWebUsage(sessionKey: String, completion: (() -> Void)?) {
        if self.orgUuid.isEmpty {
            fetchWebOrgUuid(sessionKey: sessionKey) { [weak self] result in
                guard let self = self else { return }
                switch result {
                case .success(let uuid):
                    DispatchQueue.main.async {
                        self.orgUuid = uuid
                        self.saveSettings()
                    }
                    self.fetchWebUsageDetails(sessionKey: sessionKey, orgUuid: uuid, completion: completion)
                case .failure(let error):
                    self.updateStateWithError("Failed to get organization ID: \(error.localizedDescription)")
                    completion?()
                }
            }
        } else {
            fetchWebUsageDetails(sessionKey: sessionKey, orgUuid: self.orgUuid, completion: completion)
        }
    }
    
    private func fetchWebOrgUuid(sessionKey: String, completion: @escaping (Result<String, Error>) -> Void) {
        guard let url = URL(string: "https://claude.ai/api/organizations") else {
            completion(.failure(NSError(domain: "Invalid URL", code: 0, userInfo: nil)))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
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
                completion(.failure(NSError(domain: "HTTP Error", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Server returned code \(httpResponse.statusCode). Your session key may be invalid or expired."])))
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
                    completion(.failure(NSError(domain: "No Org Found", code: 0, userInfo: [NSLocalizedDescriptionKey: "No organizations found in your Claude account."])))
                }
            } catch {
                completion(.failure(error))
            }
        }
        task.resume()
    }
    
    private func fetchWebUsageDetails(sessionKey: String, orgUuid: String, completion: (() -> Void)?) {
        guard let url = URL(string: "https://claude.ai/api/organizations/\(orgUuid)/usage") else {
            updateStateWithError("Invalid usage URL.")
            completion?()
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("sessionKey=\(sessionKey)", forHTTPHeaderField: "Cookie")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        
        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            
            if let error = error {
                self.updateStateWithError(error.localizedDescription)
                completion?()
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                self.updateStateWithError("Invalid server response.")
                completion?()
                return
            }
            
            guard httpResponse.statusCode == 200 else {
                self.updateStateWithError("HTTP Error \(httpResponse.statusCode). Check if your sessionKey has expired.")
                completion?()
                return
            }
            
            guard let data = data else {
                self.updateStateWithError("Server returned no data.")
                completion?()
                return
            }
            
            self.parseAndPublishBuckets(data: data)
            completion?()
        }
        task.resume()
    }
    
    // MARK: - CLI API Fetching
    
    private func fetchCliUsage(token: String, isRetry: Bool = false, completion: (() -> Void)?) {
        guard let url = URL(string: "https://api.anthropic.com/api/oauth/usage") else {
            updateStateWithError("Invalid OAuth usage URL.")
            completion?()
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.addValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("claude-code/2.1.34", forHTTPHeaderField: "User-Agent")
        
        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            
            if let error = error {
                self.updateStateWithError(error.localizedDescription)
                completion?()
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                self.updateStateWithError("Invalid server response.")
                completion?()
                return
            }
            
            if httpResponse.statusCode == 401 && !isRetry {
                print("HTTP 401 received. Attempting to scan keychain/refresh token...")
                self.handleCliUnauthorized(attemptedToken: token, completion: completion)
                return
            }
            
            guard httpResponse.statusCode == 200 else {
                self.updateStateWithError("HTTP Error \(httpResponse.statusCode). Your Claude Code token might have expired. Try running 'claude logout' then 'claude login'.")
                completion?()
                return
            }
            
            guard let data = data else {
                self.updateStateWithError("Server returned no data.")
                completion?()
                return
            }
            
            self.parseAndPublishBuckets(data: data)
            completion?()
        }
        task.resume()
    }
    
    private func handleCliUnauthorized(attemptedToken: String, completion: (() -> Void)?) {
        guard let credentialsJSONString = KeychainHelper.scanClaudeCodeCredentials() else {
            updateStateWithError("Could not find Claude Code credentials in your Keychain to refresh.")
            completion?()
            return
        }
        
        // Extract the latest token from keychain
        guard let currentToken = parseAccessToken(from: credentialsJSONString) else {
            updateStateWithError("Failed to parse access token from Keychain credentials.")
            completion?()
            return
        }
        
        // Case 1: The keychain already contains a different token (refreshed by CLI or other process)
        if currentToken != attemptedToken {
            print("Detected a different token in keychain. Retrying request...")
            fetchCliUsage(token: currentToken, isRetry: true, completion: completion)
            return
        }
        
        // Case 2: The token in keychain is the same, meaning we must refresh it ourselves in the background
        guard let refreshToken = parseRefreshToken(from: credentialsJSONString) else {
            updateStateWithError("Claude Code credentials do not contain a refresh token. Try running 'claude login'.")
            completion?()
            return
        }
        
        print("Token is expired. Attempting background OAuth refresh...")
        refreshOAuthToken(refreshToken: refreshToken, credentialsJSONString: credentialsJSONString) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let newAccessToken):
                print("Background OAuth refresh succeeded! Retrying request...")
                self.fetchCliUsage(token: newAccessToken, isRetry: true, completion: completion)
            case .failure(let error):
                print("Background OAuth refresh failed: \(error.localizedDescription)")
                self.updateStateWithError("Session expired (HTTP 401) and background refresh failed: \(error.localizedDescription)")
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
                completion(.failure(NSError(domain: "Invalid Response", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid server response"])))
                return
            }
            
            guard httpResponse.statusCode == 200 else {
                let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                completion(.failure(NSError(domain: "HTTP Error", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "OAuth refresh failed (HTTP \(httpResponse.statusCode)): \(body)"])))
                return
            }
            
            guard let data = data else {
                completion(.failure(NSError(domain: "No Data", code: 0, userInfo: [NSLocalizedDescriptionKey: "Server returned no data on refresh"])))
                return
            }
            
            do {
                guard let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                      let newAccessToken = json["access_token"] as? String,
                      let newRefreshToken = json["refresh_token"] as? String,
                      let expiresIn = json["expires_in"] as? Int else {
                    completion(.failure(NSError(domain: "Parse Error", code: 0, userInfo: [NSLocalizedDescriptionKey: "Response missing token fields"])))
                    return
                }
                
                // Parse the original credentials JSON, update it, and write it back
                guard let origData = credentialsJSONString.data(using: .utf8),
                      var credsDict = try JSONSerialization.jsonObject(with: origData, options: [.mutableContainers]) as? [String: Any] else {
                    completion(.failure(NSError(domain: "Parse Error", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to parse original credentials for updating"])))
                    return
                }
                
                var oauthDict = credsDict["claudeAiOauth"] as? [String: Any] ?? [String: Any]()
                oauthDict["accessToken"] = newAccessToken
                oauthDict["refreshToken"] = newRefreshToken
                oauthDict["expiresAt"] = Int64(Date().timeIntervalSince1970 + Double(expiresIn)) * 1000
                credsDict["claudeAiOauth"] = oauthDict
                
                let updatedData = try JSONSerialization.data(withJSONObject: credsDict, options: [.prettyPrinted])
                guard let updatedStr = String(data: updatedData, encoding: .utf8) else {
                    completion(.failure(NSError(domain: "Serialization Error", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to serialize updated credentials"])))
                    return
                }
                
                let writeSuccess = KeychainHelper.writeClaudeCodeCredentials(value: updatedStr)
                if !writeSuccess {
                    completion(.failure(NSError(domain: "Keychain Error", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to save refreshed credentials to Keychain"])))
                    return
                }
                
                completion(.success(newAccessToken))
                
            } catch {
                completion(.failure(error))
            }
        }
        task.resume()
    }

    
    // MARK: - Helper Parsing
    
    private func parseAndPublishBuckets(data: Data) {
        do {
            // Parse as generic JSON dict since keys vary (five_hour, seven_day, extra_usage, etc.)
            guard let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
                updateStateWithError("Unexpected response format.")
                return
            }
            var tempBuckets: [UsageBucket] = []
            
            for (key, value) in json {
                guard let val = value as? [String: Any] else { continue }
                
                if key == "extra_usage" {
                    // Extra usage has a special structure: is_enabled, used_credits, monthly_limit, utilization
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
                    // Standard bucket: five_hour, seven_day, seven_day_sonnet, etc.
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
            
            // Sort buckets: 5-hour first, then 7-day, then others, extra_usage last
            tempBuckets.sort { a, b in
                let order = ["five_hour": 0, "seven_day": 1, "seven_day_sonnet": 2, "seven_day_opus": 3, "extra_usage": 99]
                return (order[a.name] ?? 50) < (order[b.name] ?? 50)
            }
            
            DispatchQueue.main.async {
                self.usageBuckets = tempBuckets
                self.lastFetchTime = Date()
                self.isFetching = false
                self.errorMessage = nil
                
                // Cache the buckets in UserDefaults
                if let encoded = try? JSONEncoder().encode(tempBuckets) {
                    UserDefaults.standard.set(encoded, forKey: "cachedBuckets")
                }
                UserDefaults.standard.set(self.lastFetchTime, forKey: "lastFetchTime")
                
                // Export data to shared App Group for WidgetKit widget
                self.updateSharedWidgetData()
            }
        } catch {
            updateStateWithError("Failed to parse usage data: \(error.localizedDescription)")
        }
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
    
    private func updateSharedWidgetData() {
        let session = self.usageBuckets.first(where: { $0.name == "five_hour" })
        let weekly = self.usageBuckets.first(where: { $0.name == "seven_day" })
        
        let sessionUtil = session?.utilization ?? 0.0
        let sessionTime = session?.timeRemainingString ?? "No data"
        let weeklyUtil = weekly?.utilization ?? 0.0
        let weeklyTime = weekly?.timeRemainingString ?? "No data"
        
        let info = SharedUsageInfo(
            sessionUtilization: sessionUtil,
            sessionTimeRemaining: sessionTime,
            weeklyUtilization: weeklyUtil,
            weeklyTimeRemaining: weeklyTime
        )
        
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.Mudit01100001.claude-usage") else {
            // Signal WidgetKit to refresh anyway (it will fetch via HTTP)
            WidgetCenter.shared.reloadAllTimelines()
            return
        }
        
        // Ensure shared container directory exists
        try? FileManager.default.createDirectory(at: containerURL, withIntermediateDirectories: true, attributes: nil)
        
        let fileURL = containerURL.appendingPathComponent("usage.json")
        do {
            let data = try JSONEncoder().encode(info)
            try data.write(to: fileURL)
            // Signal WidgetKit to refresh all timeline widgets immediately
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
        let session = self.appState.usageBuckets.first(where: { $0.name == "five_hour" })
        let weekly = self.appState.usageBuckets.first(where: { $0.name == "seven_day" })
        
        let sessionUtil = session?.utilization ?? 0.0
        let sessionTime = session?.timeRemainingString ?? "No data"
        let weeklyUtil = weekly?.utilization ?? 0.0
        let weeklyTime = weekly?.timeRemainingString ?? "No data"
        
        let info = SharedUsageInfo(
            sessionUtilization: sessionUtil,
            sessionTimeRemaining: sessionTime,
            weeklyUtilization: weeklyUtil,
            weeklyTimeRemaining: weeklyTime
        )
        
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

