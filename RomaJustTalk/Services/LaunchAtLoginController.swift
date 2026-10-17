import LaunchAtLogin
import SwiftUI

@MainActor
final class LaunchAtLoginController: ObservableObject {
    @Published var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            writeEnabled(isEnabled)
        }
    }

    private let writeEnabled: (Bool) -> Void

    init(
        readEnabled: () -> Bool = { LaunchAtLogin.isEnabled },
        writeEnabled: @escaping (Bool) -> Void = { LaunchAtLogin.isEnabled = $0 }
    ) {
        self.writeEnabled = writeEnabled
        self.isEnabled = readEnabled()
    }
}
