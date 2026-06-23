import SwiftUI
import VoiceInkCore

// MARK: - Shared Analysis Logic

enum PanelMode {
    case info
    case analysis
}

struct PerformanceAnalyzer {
    static func getMacModel() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var machine = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &machine, &size, nil, 0)
        return String(cString: machine)
    }

    static func getCPUInfo() -> String {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var buffer = [CChar](repeating: 0, count: size)
        sysctlbyname("machdep.cpu.brand_string", &buffer, &size, nil, 0)
        return String(cString: buffer)
    }

    static func getMemoryInfo() -> String {
        let totalMemory = ProcessInfo.processInfo.physicalMemory
        return VoiceInkPerformancePresentation.physicalMemoryText(byteCount: totalMemory)
    }
}

struct MetricCardBackground: View {
    let color: Color
    
    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(.regularMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(color.opacity(0.08))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color(NSColor.separatorColor).opacity(0.35), lineWidth: 1)
            }
    }
}
