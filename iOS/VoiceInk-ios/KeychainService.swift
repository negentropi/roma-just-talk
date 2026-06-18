import Foundation
import Security
import VoiceInkCore

struct KeychainService {
    
    static func save(key: String, data: Data) -> OSStatus {
        SecItemDelete(VoiceInkKeychainQuery.base(account: key) as CFDictionary)

        return SecItemAdd(
            VoiceInkKeychainQuery.add(data: data, account: key) as CFDictionary,
            nil
        )
    }
    
    static func load(key: String) -> Data? {
        var dataTypeRef: AnyObject? = nil
        
        let status: OSStatus = SecItemCopyMatching(
            VoiceInkKeychainQuery.copyData(account: key) as CFDictionary,
            &dataTypeRef
        )
        
        if status == noErr {
            return dataTypeRef as! Data?
        } else {
            return nil
        }
    }
    
    static func delete(key: String) -> OSStatus {
        SecItemDelete(VoiceInkKeychainQuery.base(account: key) as CFDictionary)
    }
}
