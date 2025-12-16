import LocalAuthentication

class AuthenticationService: ObservableObject {
    @Published var gitlabURL: String {
        didSet {
            UserDefaults.standard.set(gitlabURL, forKey: "gitlabURL")
        }
    }
    
    @Published var isAuthenticated: Bool = false
    @Published var isLocked: Bool = true // New state: Token exists but locked
    
    private let serviceName = "com.gitlabmenubar.auth"
    private let accountName = "gitlabToken"
    
    var hasToken: Bool {
        // FAST check if we can read the token
        return loadToken(isFastCheck: true) != nil
    }
    
    init() {
        self.gitlabURL = UserDefaults.standard.string(forKey: "gitlabURL") ?? "https://gitlab.com"
        self.isAuthenticated = false
        // Determine initial state
        if hasToken {
            self.isLocked = true // We have a token, but need bio to unlock
        } else {
            self.isLocked = false // No token, goes to setup
        }
    }
    
    func unlock() {
        let context = LAContext()
        var error: NSError?
        
        // check if can evaluate
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            let reason = "Authenticate to access your GitLab projects"
            
            context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, authenticationError in
                DispatchQueue.main.async {
                    if success {
                        self.isLocked = false
                        self.isAuthenticated = true
                    } else {
                        // Failed to auth
                        print("Bio Auth failed")
                    }
                }
            }
        } else {
            // No biometrics available? Fallback or just unlock?
            // For this app, let's fall back to password or just unlock if no bio hardware
            print("Biometrics not available")
            self.isLocked = false
            self.isAuthenticated = true
        }
    }
    
    func saveToken(_ token: String) -> Bool {
        guard !token.isEmpty else { return false }
        let data = Data(token.utf8)
        
        // Remove existing item if present
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: accountName
        ]
        SecItemDelete(query as CFDictionary)
        
        // Add new item - STANDARD, NO ACL
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: accountName,
            kSecValueData as String: data
        ]
        
        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status == errSecSuccess {
            DispatchQueue.main.async {
                self.isAuthenticated = true
                self.isLocked = false
            }
            return true
        } else {
            print("Keychain save error: \(status)")
            return false
        }
    }
    
    func loadToken(isFastCheck: Bool = false) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: accountName,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        
        if status == errSecSuccess, let data = dataTypeRef as? Data {
            return String(data: data, encoding: .utf8)
        }
        return nil
    }
    
    func logout() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: accountName
        ]
        
        SecItemDelete(query as CFDictionary)
        DispatchQueue.main.async {
            self.isAuthenticated = false
            self.isLocked = false
        }
    }
}
