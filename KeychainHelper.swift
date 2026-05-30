import Foundation
import Security

class KeychainHelper {
    
    // Save password/token securely to Keychain
    class func save(service: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }
        
        let query = [
            kSecClass as String: kSecClassGenericPassword as String,
            kSecAttrService as String: service
        ] as [String: Any]
        
        // Delete existing item first
        SecItemDelete(query as CFDictionary)
        
        let addQuery = [
            kSecClass as String: kSecClassGenericPassword as String,
            kSecAttrService as String: service,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock as String
        ] as [String: Any]
        
        SecItemAdd(addQuery as CFDictionary, nil)
    }
    
    // Load password/token from Keychain
    class func load(service: String) -> String? {
        let query = [
            kSecClass as String: kSecClassGenericPassword as String,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ] as [String: Any]
        
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        
        if status == errSecSuccess, let data = dataTypeRef as? Data {
            return String(data: data, encoding: .utf8)
        }
        return nil
    }
    
    // Delete password/token from Keychain
    class func delete(service: String) {
        let query = [
            kSecClass as String: kSecClassGenericPassword as String,
            kSecAttrService as String: service
        ] as [String: Any]
        SecItemDelete(query as CFDictionary)
    }
    
    // Scan for Claude Code credentials using multiple methods
    // Method 1: Use `security` CLI tool (avoids password prompt if already authorized)
    // Method 2: Use SecItemCopyMatching (may trigger Keychain password prompt)
    // Method 3: Read from ~/.claude/.credentials.json file fallback
    class func scanClaudeCodeCredentials() -> String? {
        // Method 1: Try the security command-line tool
        if let data = readCredentialsViaCLI() {
            return data
        }
        
        // Method 2: Try SecItemCopyMatching API 
        if let data = load(service: "Claude Code-credentials") {
            return data
        }
        if let data = load(service: "claude-code") {
            return data
        }
        
        // Method 3: Try reading from credentials file
        if let data = readCredentialsFromFile() {
            return data
        }
        
        return nil
    }
    
    // Read credentials via the `security` command-line tool
    private class func readCredentialsViaCLI() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe() // Suppress stderr
        
        do {
            try process.run()
            process.waitUntilExit()
            
            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !output.isEmpty {
                    return output
                }
            }
        } catch {
            // Silently fail and try next method
        }
        
        return nil
    }
    
    // Read credentials from ~/.claude/.credentials.json
    private class func readCredentialsFromFile() -> String? {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let credentialsPath = homeDir.appendingPathComponent(".claude/.credentials.json")
        
        if FileManager.default.fileExists(atPath: credentialsPath.path) {
            do {
                let contents = try String(contentsOf: credentialsPath, encoding: .utf8)
                if !contents.isEmpty {
                    return contents
                }
            } catch {
                // Silently fail
            }
        }
        
        return nil
    }
    
    // Write Claude Code credentials to Keychain and/or file
    class func writeClaudeCodeCredentials(value: String) -> Bool {
        var success = false
        
        if writeCredentialsViaCLI(value: value) {
            success = true
        }
        
        if writeCredentialsToFile(value: value) {
            success = true
        }
        
        return success
    }
    
    private class func writeCredentialsViaCLI(value: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        let username = NSUserName()
        process.arguments = ["add-generic-password", "-a", username, "-s", "Claude Code-credentials", "-w", value, "-U"]
        
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
    
    private class func writeCredentialsToFile(value: String) -> Bool {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let credentialsPath = homeDir.appendingPathComponent(".claude/.credentials.json")
        
        if FileManager.default.fileExists(atPath: credentialsPath.path) {
            do {
                try value.write(to: credentialsPath, atomically: true, encoding: .utf8)
                return true
            } catch {
                // Silently fail
            }
        }
        return false
    }
}


