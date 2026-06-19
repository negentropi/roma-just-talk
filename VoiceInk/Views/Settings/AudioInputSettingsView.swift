import SwiftUI
import VoiceInkCore

struct AudioInputSettingsView: View {
    @ObservedObject var audioDeviceManager = AudioDeviceManager.shared
    @Environment(\.colorScheme) private var colorScheme
    private let presentation = VoiceInkMacOSAudioInputSettingsPresentation.macOS
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                heroSection
                mainContent
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    private var mainContent: some View {
        VStack(spacing: 40) {
            inputModeSection

            switch audioDeviceManager.inputMode {
            case .systemDefault:
                systemDefaultSection
            case .custom:
                customDeviceSection
            case .prioritized:
                prioritizedDevicesSection
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 40)
    }
    
    private var heroSection: some View {
        CompactHeroSection(
            icon: presentation.heroSystemImageName,
            title: presentation.heroTitle,
            description: presentation.heroDescription
        )
    }
    
    private var inputModeSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(presentation.inputModeSectionTitle)
                .font(.title2)
                .fontWeight(.semibold)
            
            HStack(spacing: 20) {
                ForEach(VoiceInkAudioInputMode.allCases) { mode in
                    InputModeCard(
                        mode: mode,
                        isSelected: audioDeviceManager.inputMode == mode,
                        action: { audioDeviceManager.selectInputMode(mode) }
                    )
                }
            }
        }
    }
    
    private var systemDefaultSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(presentation.currentDeviceSectionTitle)
                .font(.title2)
                .fontWeight(.semibold)

            HStack {
                Image(systemName: presentation.currentDeviceSystemImageName)
                    .foregroundStyle(.secondary)

                Text(audioDeviceManager.getSystemDefaultDeviceName() ?? presentation.noDeviceAvailableText)
                    .foregroundStyle(.primary)

                Spacer()

                Label(presentation.activeStatusTitle, systemImage: presentation.activeStatusSystemImageName)
                    .font(.caption)
                    .foregroundStyle(.green)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(.green.opacity(0.1))
                    )
            }
            .padding()
            .background(CardBackground(isSelected: false))
        }
    }

    private var customDeviceSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text(presentation.availableDevicesSectionTitle)
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                Button(action: { audioDeviceManager.loadAvailableDevices() }) {
                    Label(presentation.refreshButtonTitle, systemImage: presentation.refreshButtonSystemImageName)
                }
                .buttonStyle(.borderless)
            }

            VStack(spacing: 12) {
                ForEach(audioDeviceManager.availableDevices, id: \.id) { device in
                    DeviceSelectionCard(
                        name: device.name,
                        isSelected: audioDeviceManager.selectedDeviceID == device.id,
                        isActive: audioDeviceManager.getCurrentDevice() == device.id,
                        presentation: presentation
                    ) {
                        audioDeviceManager.selectDevice(id: device.id)
                    }
                }
            }
        }
    }
    
    private var prioritizedDevicesSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            if audioDeviceManager.availableDevices.isEmpty {
                emptyDevicesState
            } else {
                prioritizedDevicesContent
                Divider().padding(.vertical, 8)
                availableDevicesContent
            }
        }
    }
    
    private var prioritizedDevicesContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(presentation.prioritizedDevicesSectionTitle)
                    .font(.title2)
                    .fontWeight(.semibold)
                Text(presentation.prioritizedDevicesDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            if audioDeviceManager.prioritizedDevices.isEmpty {
                Text(presentation.noPrioritizedDevicesText)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                prioritizedDevicesList
            }
        }
    }
    
    private var availableDevicesContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(presentation.availableDevicesSectionTitle)
                .font(.title2)
                .fontWeight(.semibold)
            
            availableDevicesList
        }
    }
    
    private var emptyDevicesState: some View {
        VStack(spacing: 16) {
            Image(systemName: presentation.emptyDevicesSystemImageName)
                .font(.system(size: 48))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
            
            VStack(spacing: 8) {
                Text(presentation.emptyDevicesTitle)
                    .font(.headline)
                Text(presentation.emptyDevicesDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(40)
        .background(CardBackground(isSelected: false))
    }
    
    private var prioritizedDevicesList: some View {
        VStack(spacing: 12) {
            ForEach(VoiceInkAudioInputPriorityPolicy.sortedDevices(audioDeviceManager.prioritizedDevices)) { device in
                devicePriorityCard(for: device)
            }
        }
    }
    
    private func devicePriorityCard(for prioritizedDevice: VoiceInkAudioInputPriorityDevice) -> some View {
        let device = audioDeviceManager.availableDevices.first(where: { $0.uid == prioritizedDevice.id })
        return DevicePriorityCard(
            name: prioritizedDevice.name,
            priority: prioritizedDevice.priority,
            isActive: device.map { audioDeviceManager.getCurrentDevice() == $0.id } ?? false,
            isPrioritized: true,
            isAvailable: device != nil,
            presentation: presentation,
            canMoveUp: prioritizedDevice.priority > 0,
            canMoveDown: prioritizedDevice.priority < audioDeviceManager.prioritizedDevices.count - 1,
            onTogglePriority: { audioDeviceManager.removePrioritizedDevice(id: prioritizedDevice.id) },
            onMoveUp: { moveDeviceUp(prioritizedDevice) },
            onMoveDown: { moveDeviceDown(prioritizedDevice) }
        )
    }
    
    private var availableDevicesList: some View {
        let unprioritizedDevices = audioDeviceManager.availableDevices.filter { device in
            !audioDeviceManager.prioritizedDevices.contains { $0.id == device.uid }
        }
        
        return Group {
            if unprioritizedDevices.isEmpty {
                Text(presentation.noAdditionalDevicesText)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(unprioritizedDevices, id: \.id) { device in
                    DevicePriorityCard(
                        name: device.name,
                        priority: nil,
                        isActive: audioDeviceManager.getCurrentDevice() == device.id,
                        isPrioritized: false,
                        isAvailable: true,
                        presentation: presentation,
                        canMoveUp: false,
                        canMoveDown: false,
                        onTogglePriority: { audioDeviceManager.addPrioritizedDevice(uid: device.uid, name: device.name) },
                        onMoveUp: {},
                        onMoveDown: {}
                    )
                }
            }
        }
    }
    
    private func moveDeviceUp(_ device: VoiceInkAudioInputPriorityDevice) {
        let updatedDevices = VoiceInkAudioInputPriorityPolicy.moveDevice(
            id: device.id,
            direction: .up,
            in: audioDeviceManager.prioritizedDevices
        )
        guard updatedDevices != audioDeviceManager.prioritizedDevices else { return }
        audioDeviceManager.updatePriorities(devices: updatedDevices)
    }
    
    private func moveDeviceDown(_ device: VoiceInkAudioInputPriorityDevice) {
        let updatedDevices = VoiceInkAudioInputPriorityPolicy.moveDevice(
            id: device.id,
            direction: .down,
            in: audioDeviceManager.prioritizedDevices
        )
        guard updatedDevices != audioDeviceManager.prioritizedDevices else { return }
        audioDeviceManager.updatePriorities(devices: updatedDevices)
    }
}

struct InputModeCard: View {
    let mode: VoiceInkAudioInputMode
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: mode.iconSystemName)
                    .font(.system(size: 28))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isSelected ? .blue : .secondary)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(mode.title)
                        .font(.headline)
                    
                    Text(mode.description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(CardBackground(isSelected: isSelected))
        }
        .buttonStyle(.plain)
    }
}

struct DeviceSelectionCard: View {
    let name: String
    let isSelected: Bool
    let isActive: Bool
    let presentation: VoiceInkMacOSAudioInputSettingsPresentation
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isSelected ? .blue : .secondary)
                    .font(.system(size: 18))
                
                Text(name)
                    .foregroundStyle(.primary)
                
                Spacer()
                
                if isActive {
                    Label(presentation.activeStatusTitle, systemImage: presentation.activeStatusSystemImageName)
                        .font(.caption)
                        .foregroundStyle(.green)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(.green.opacity(0.1))
                        )
                }
            }
            .padding()
            .background(CardBackground(isSelected: isSelected))
        }
        .buttonStyle(.plain)
    }
}

struct DevicePriorityCard: View {
    let name: String
    let priority: Int?
    let isActive: Bool
    let isPrioritized: Bool
    let isAvailable: Bool
    let presentation: VoiceInkMacOSAudioInputSettingsPresentation
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onTogglePriority: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    
    var body: some View {
        HStack {
            // Priority number or dash
            if let priority = priority {
                Text(presentation.priorityDisplayText(for: priority))
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 24)
            } else {
                Text(presentation.unprioritizedPriorityPlaceholder)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 24)
            }
            
            // Device name
            Text(name)
                .foregroundStyle(isAvailable ? .primary : .secondary)
            
            Spacer()
            
            // Status and Controls
            HStack(spacing: 12) {
                // Active status
                if isActive {
                    Label(presentation.activeStatusTitle, systemImage: presentation.activeStatusSystemImageName)
                        .font(.caption)
                        .foregroundStyle(.green)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(.green.opacity(0.1))
                        )
                } else if !isAvailable && isPrioritized {
                    Label(presentation.unavailableStatusTitle, systemImage: presentation.unavailableStatusSystemImageName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Color(.windowBackgroundColor).opacity(0.4))
                        )
                }
                
                // Priority controls (only show if prioritized)
                if isPrioritized {
                    HStack(spacing: 2) {
                        Button(action: onMoveUp) {
                            Image(systemName: presentation.moveUpSystemImageName)
                                .foregroundStyle(canMoveUp ? .blue : .secondary.opacity(0.5))
                        }
                        .disabled(!canMoveUp)
                        
                        Button(action: onMoveDown) {
                            Image(systemName: presentation.moveDownSystemImageName)
                                .foregroundStyle(canMoveDown ? .blue : .secondary.opacity(0.5))
                        }
                        .disabled(!canMoveDown)
                    }
                }
                
                // Toggle priority button
                Button(action: onTogglePriority) {
                    Image(systemName: isPrioritized ? presentation.removePrioritySystemImageName : presentation.addPrioritySystemImageName)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(isPrioritized ? .red : .blue)
                }
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(CardBackground(isSelected: false))
    }
} 
