import SwiftUI

@MainActor
final class PermissionNotificationSuppression {
    static let shared = PermissionNotificationSuppression()

    private var activeScopeIDs: Set<UUID> = []

    var isSuppressingPermissionPrompts: Bool {
        !activeScopeIDs.isEmpty
    }

    init() {}

    func beginScope() -> UUID {
        let id = UUID()
        activeScopeIDs.insert(id)
        return id
    }

    func endScope(_ id: UUID?) {
        guard let id else { return }
        activeScopeIDs.remove(id)
    }
}

private struct PermissionNotificationSuppressionModifier: ViewModifier {
    @State private var scopeID: UUID?

    func body(content: Content) -> some View {
        content
            .onAppear {
                guard scopeID == nil else { return }
                scopeID = PermissionNotificationSuppression.shared.beginScope()
            }
            .onDisappear {
                PermissionNotificationSuppression.shared.endScope(scopeID)
                scopeID = nil
            }
    }
}

extension View {
    func suppressesPermissionPromptNotifications() -> some View {
        modifier(PermissionNotificationSuppressionModifier())
    }
}
