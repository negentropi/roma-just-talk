import Foundation

public enum VoiceInkSystemArchitecture {
    public static var isIntelMac: Bool {
        #if os(macOS) && arch(x86_64)
        return true
        #else
        return false
        #endif
    }

    public static var macOSDisplayName: String {
        #if arch(arm64)
        return "Apple Silicon (ARM64)"
        #elseif arch(x86_64)
        return "Intel (x86_64)"
        #else
        return "Unknown"
        #endif
    }
}
