import Foundation
import Security
import VoiceInkCore

struct KeychainService {
    
    static func save(key: String, data: Data) -> OSStatus {
        VoiceInkKeychainDataStore.saveData(data, account: key)
    }
    
    static func load(key: String) -> Data? {
        VoiceInkKeychainDataStore.loadData(account: key).data
    }
    
    static func delete(key: String) -> OSStatus {
        VoiceInkKeychainDataStore.delete(account: key)
    }
}
