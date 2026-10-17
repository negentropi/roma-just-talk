import Foundation
import SwiftUI
import RomaCore

// MARK: - UI Extensions
extension RomaCustomPrompt {
    func promptIcon(isSelected: Bool, onTap: @escaping () -> Void, onEdit: ((RomaCustomPrompt) -> Void)? = nil, onDelete: ((RomaCustomPrompt) -> Void)? = nil) -> some View {
        VStack(spacing: 8) {
            ZStack {
                // Dynamic background with blur effect
                RoundedRectangle(cornerRadius: 14)
                    .fill(
                        LinearGradient(
                            gradient: isSelected ?
                                Gradient(colors: [
                                    Color.accentColor.opacity(0.9),
                                    Color.accentColor.opacity(0.7)
                                ]) :
                                Gradient(colors: [
                                    Color(NSColor.controlBackgroundColor).opacity(0.95),
                                    Color(NSColor.controlBackgroundColor).opacity(0.85)
                                ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        isSelected ?
                                            Color.white.opacity(0.3) : Color.white.opacity(0.15),
                                        isSelected ?
                                            Color.white.opacity(0.1) : Color.white.opacity(0.05)
                                    ]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                    .shadow(
                        color: isSelected ?
                            Color.accentColor.opacity(0.4) : Color.black.opacity(0.1),
                        radius: isSelected ? 10 : 6,
                        x: 0,
                        y: 3
                    )
                
                // Decorative background elements
                Circle()
                    .fill(
                        RadialGradient(
                            gradient: Gradient(colors: [
                                isSelected ?
                                    Color.white.opacity(0.15) : Color.white.opacity(0.08),
                                Color.clear
                            ]),
                            center: .center,
                            startRadius: 1,
                            endRadius: 25
                        )
                    )
                    .frame(width: 50, height: 50)
                    .offset(x: -15, y: -15)
                    .blur(radius: 2)
                
                // Icon with enhanced effects
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: isSelected ?
                                [Color.white, Color.white.opacity(0.9)] :
                                [Color.primary.opacity(0.9), Color.primary.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(
                        color: isSelected ?
                            Color.white.opacity(0.5) : Color.clear,
                        radius: 4
                    )
                    .shadow(
                        color: isSelected ?
                            Color.accentColor.opacity(0.5) : Color.clear,
                        radius: 3
                    )
            }
            .frame(width: 48, height: 48)
            
            // Enhanced title styling
            VStack(spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(isSelected ?
                        .primary : .secondary)
                    .lineLimit(1)
                    .frame(maxWidth: 70)
                
                // Trigger word section with consistent height
                ZStack(alignment: .center) {
                    if let triggerSummary = RomaCustomPromptPresentation.triggerSummary(for: triggerWords) {
                        HStack(spacing: 2) {
                            Image(systemName: triggerSummary.iconSystemName)
                                .font(.system(size: 7))
                                .foregroundColor(isSelected ? .accentColor.opacity(0.9) : .secondary.opacity(0.7))

                            Text(triggerSummary.text)
                                .font(.system(size: 8, weight: .regular))
                                .foregroundColor(isSelected ? .primary.opacity(0.8) : .secondary.opacity(0.7))
                                .lineLimit(1)
                        }
                        .frame(maxWidth: 70)
                    }
                }
                .frame(height: 16)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .scaleEffect(isSelected ? 1.05 : 1.0)
        .onTapGesture(count: 2) {
            // Double tap to edit
            if let onEdit = onEdit {
                onEdit(self)
            }
        }
        .onTapGesture(count: 1) {
            // Single tap to select
            onTap()
        }
        .contextMenu {
            if onEdit != nil || onDelete != nil {
                if let onEdit = onEdit {
                    Button {
                        onEdit(self)
                    } label: {
                        Label(
                            RomaCustomPromptPresentation.editActionTitle,
                            systemImage: RomaCustomPromptPresentation.editActionSystemImageName
                        )
                    }
                }
                
                if let onDelete = onDelete, !isPredefined {
                    Button(role: .destructive) {
                        let alert = NSAlert()
                        alert.messageText = RomaCustomPromptPresentation.deletePromptConfirmationTitle
                        alert.informativeText = RomaCustomPromptPresentation.deletePromptConfirmationMessage(promptTitle: title)
                        alert.alertStyle = .warning
                        alert.addButton(withTitle: RomaCustomPromptPresentation.deleteActionTitle)
                        alert.addButton(withTitle: RomaCustomPromptPresentation.cancelActionTitle)
                        
                        let response = alert.runModal()
                        if response == .alertFirstButtonReturn {
                            onDelete(self)
                        }
                    } label: {
                        Label(
                            RomaCustomPromptPresentation.deleteActionTitle,
                            systemImage: RomaCustomPromptPresentation.deleteActionSystemImageName
                        )
                    }
                }
            }
        }
    }
    
    // Static method to create the prompt-add button with the same styling as the prompt icons.
    static func addNewButton(action: @escaping () -> Void) -> some View {
        VStack(spacing: 8) {
            ZStack {
                // Dynamic background with blur effect - same styling as promptIcon
                RoundedRectangle(cornerRadius: 14)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color(NSColor.controlBackgroundColor).opacity(0.95),
                                Color(NSColor.controlBackgroundColor).opacity(0.85)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color.white.opacity(0.15),
                                        Color.white.opacity(0.05)
                                    ]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                    .shadow(
                        color: Color.black.opacity(0.1),
                        radius: 6,
                        x: 0,
                        y: 3
                    )
                
                // Decorative background elements (same as in promptIcon)
                Circle()
                    .fill(
                        RadialGradient(
                            gradient: Gradient(colors: [
                                Color.white.opacity(0.08),
                                Color.clear
                            ]),
                            center: .center,
                            startRadius: 1,
                            endRadius: 25
                        )
                    )
                    .frame(width: 50, height: 50)
                    .offset(x: -15, y: -15)
                    .blur(radius: 2)
                
                // Plus icon with same styling as the normal icons
                Image(systemName: RomaCustomPromptPresentation.addPromptSystemImageName)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.accentColor.opacity(0.9), Color.accentColor.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .frame(width: 48, height: 48)
            
            // Text label with matching styling
            VStack(spacing: 2) {
                Text(RomaCustomPromptPresentation.addPromptTitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: 70)
                
                // Empty space matching the trigger word area height
                Spacer()
                    .frame(height: 16)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
    }
}
