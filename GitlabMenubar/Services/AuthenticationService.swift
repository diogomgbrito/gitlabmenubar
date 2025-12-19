import LocalAuthentication

class AuthenticationService: ObservableObject {
    @Published var gitlabURL: String {
        didSet {
            UserDefaults.standard.set(gitlabURL, forKey: "gitlabURL")
        }
    }
    
    @Published var isAuthenticated: Bool = false
    
    private let serviceName = "com.gitlabmenubar.auth"
    private let accountName = "gitlabToken"
    
    @Published var currentUser: GitLabClient.User?
    
    var hasToken: Bool {
        return loadToken() != nil
    }
    
    init() {
        self.gitlabURL = UserDefaults.standard.string(forKey: "gitlabURL") ?? "https://gitlab.com"
        // If we have a token, we're authenticated
        self.isAuthenticated = hasToken
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
        
        // Add new item
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
            }
            return true
        } else {
            print("Keychain save error: \(status)")
            return false
        }
    }
    
    func loadToken() -> String? {
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
        }
    }
}
