import Foundation
import CoreAudio
import AVFoundation
import os
import VoiceInkCore

class AudioDeviceManager: ObservableObject {
    private let logger = Logger(
        subsystem: VoiceInkAppIdentity.loggingSubsystem,
        category: VoiceInkMacOSLogCategory.audioDeviceManager
    )
    @Published var availableDevices: [(id: AudioDeviceID, uid: String, name: String)] = []
    @Published var selectedDeviceID: AudioDeviceID?
    @Published var inputMode: VoiceInkAudioInputMode = .defaultMode
    @Published var prioritizedDevices: [VoiceInkAudioInputPriorityDevice] = []

    var isRecordingActive: Bool = false

    static let shared = AudioDeviceManager()

    init() {
        loadPrioritizedDevices()
        inputMode = VoiceInkAudioInputPreference.inputMode()

        loadAvailableDevices { [weak self] in
            self?.initializeSelectedDevice()
        }

        setupDeviceChangeNotifications()
    }

    /// Returns the current system default input device from macOS
    func getSystemDefaultDevice() -> AudioDeviceID? {
        var deviceID = AudioDeviceID(0)
        var propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &propertySize,
            &deviceID
        )

        guard status == noErr, deviceID != 0 else {
            logger.error("\(VoiceInkAudioInputDiagnostics.systemDefaultDeviceLookupFailedMessage(status: status), privacy: .public)")
            return nil
        }
        return deviceID
    }

    func getSystemDefaultDeviceName() -> String? {
        guard let deviceID = getSystemDefaultDevice() else { return nil }
        return getDeviceName(deviceID: deviceID)
    }
    
    private func initializeSelectedDevice() {
        switch inputMode {
        case .systemDefault:
            logger.notice("\(VoiceInkAudioInputDiagnostics.systemDefaultModeMessage, privacy: .public)")
        case .prioritized:
            selectHighestPriorityAvailableDevice()
        case .custom:
            if let savedUID = VoiceInkAudioInputPreference.selectedDeviceUID() {
                if let device = availableDevices.first(where: { $0.uid == savedUID }) {
                    selectedDeviceID = device.id
                } else {
                    logger.warning("\(VoiceInkAudioInputDiagnostics.savedDeviceUnavailableMessage(uid: savedUID), privacy: .public)")
                    VoiceInkAudioInputPreference.clearSelectedDeviceUID()
                    fallbackToDefaultDevice()
                }
            } else {
                fallbackToDefaultDevice()
            }
        }
    }
    
    private func isDeviceAvailable(_ deviceID: AudioDeviceID) -> Bool {
        return availableDevices.contains { $0.id == deviceID }
    }
    
    private func fallbackToDefaultDevice() {
        logger.notice("\(VoiceInkAudioInputDiagnostics.currentDeviceUnavailableSelectingNewDeviceMessage, privacy: .public)")

        guard let newDeviceID = findBestAvailableDevice() else {
            logger.error("\(VoiceInkAudioInputDiagnostics.noInputDevicesAvailableMessage, privacy: .public)")
            selectedDeviceID = nil
            notifyDeviceChange()
            return
        }

        let newDeviceName = getDeviceName(deviceID: newDeviceID) ?? VoiceInkAudioInputDiagnostics.unknownDeviceName
        logger.notice("\(VoiceInkAudioInputDiagnostics.autoSelectingNewDeviceMessage(name: newDeviceName), privacy: .public)")
        selectDevice(id: newDeviceID)
    }

    func findBestAvailableDevice() -> AudioDeviceID? {
        safeAutomaticDevice()
    }

    func isBuiltInDevice(_ deviceID: AudioDeviceID) -> Bool {
        VoiceInkAudioInputAutomaticSelectionPolicy.isBuiltInDevice(
            transportIsBuiltIn: getTransportType(deviceID: deviceID) == kAudioDeviceTransportTypeBuiltIn,
            uid: getDeviceUID(deviceID: deviceID)
        )
    }
    
    func loadAvailableDevices(completion: (() -> Void)? = nil) {
        var propertySize: UInt32 = 0
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var result = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &propertySize
        )
        
        let deviceCount = Int(propertySize) / MemoryLayout<AudioDeviceID>.size
        
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        
        result = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &propertySize,
            &deviceIDs
        )
        
        if result != noErr {
            logger.error("\(VoiceInkAudioInputDiagnostics.audioDevicesLoadFailedMessage(status: result), privacy: .public)")
            return
        }
        
        let devices = deviceIDs.compactMap { deviceID -> (id: AudioDeviceID, uid: String, name: String)? in
            guard let name = getDeviceName(deviceID: deviceID),
                  let uid = getDeviceUID(deviceID: deviceID),
                  isValidInputDevice(deviceID: deviceID) else {
                return nil
            }
            return (id: deviceID, uid: uid, name: name)
        }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.availableDevices = devices.map { ($0.id, $0.uid, $0.name) }
            if let currentID = self.selectedDeviceID, !devices.contains(where: { $0.id == currentID }) {
                self.logger.warning("\(VoiceInkAudioInputDiagnostics.currentDeviceUnavailableMessage, privacy: .public)")
                if !self.isRecordingActive {
                    if self.inputMode == .prioritized {
                        self.selectHighestPriorityAvailableDevice()
                    } else {
                        self.fallbackToDefaultDevice()
                    }
                }
            }
            completion?()
        }
    }
    
    func getDeviceName(deviceID: AudioDeviceID) -> String? {
        let name: CFString? = getDeviceProperty(deviceID: deviceID,
                                              selector: kAudioDevicePropertyDeviceNameCFString)
        return name as String?
    }

    func getDeviceModelName(deviceID: AudioDeviceID) -> String? {
        let name: CFString? = getDeviceProperty(
            deviceID: deviceID,
            selector: kAudioObjectPropertyModelName
        )
        return name as String?
    }
    
    private func isValidInputDevice(deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        var propertySize: UInt32 = 0
        var result = AudioObjectGetPropertyDataSize(
            deviceID,
            &address,
            0,
            nil,
            &propertySize
        )

        if result != noErr {
            logger.error("\(VoiceInkAudioInputDiagnostics.inputCapabilityCheckFailedMessage(deviceID: deviceID, status: result), privacy: .public)")
            return false
        }

        let bufferList = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: Int(propertySize))
        defer { bufferList.deallocate() }

        result = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &propertySize,
            bufferList
        )

        if result != noErr {
            logger.error("\(VoiceInkAudioInputDiagnostics.streamConfigurationLoadFailedMessage(deviceID: deviceID, status: result), privacy: .public)")
            return false
        }

        let bufferCount = Int(bufferList.pointee.mNumberBuffers)
        return bufferCount > 0
    }

    func selectDevice(id: AudioDeviceID) {
        if let deviceToSelect = availableDevices.first(where: { $0.id == id }) {
            let uid = deviceToSelect.uid
            DispatchQueue.main.async {
                self.selectedDeviceID = id
                VoiceInkAudioInputPreference.saveSelectedDeviceUID(uid)
                self.notifyDeviceChange()
            }
        } else {
            logger.error("\(VoiceInkAudioInputDiagnostics.unavailableDeviceSelectionAttemptedMessage(deviceID: id), privacy: .public)")
            fallbackToDefaultDevice()
        }
    }

    func selectDeviceAndSwitchToCustomMode(id: AudioDeviceID) {
        if let deviceToSelect = availableDevices.first(where: { $0.id == id }) {
            let uid = deviceToSelect.uid
            DispatchQueue.main.async {
                self.inputMode = .custom
                self.selectedDeviceID = id
                VoiceInkAudioInputPreference.saveInputMode(.custom)
                VoiceInkAudioInputPreference.saveSelectedDeviceUID(uid)
                self.notifyDeviceChange()
            }
        } else {
            logger.error("\(VoiceInkAudioInputDiagnostics.unavailableDeviceSelectionAttemptedMessage(deviceID: id), privacy: .public)")
            fallbackToDefaultDevice()
        }
    }

    func selectInputMode(_ mode: VoiceInkAudioInputMode) {
        inputMode = mode
        VoiceInkAudioInputPreference.saveInputMode(mode)

        if let deviceID = deviceIDToSelectWhenChangingMode(mode) {
            selectDevice(id: deviceID)
        }

        notifyDeviceChange()
    }
    
    func getCurrentDevice() -> AudioDeviceID {
        switch inputMode {
        case .systemDefault:
            return VoiceInkAudioInputSelectionPolicy.currentDeviceID(
                inputMode: inputMode,
                selectedDeviceID: selectedDeviceID,
                selectedDeviceIsAvailable: selectedDeviceIsAvailable,
                priorityDeviceID: nil,
                automaticDeviceID: nil,
                systemDefaultDeviceID: safeAutomaticDevice(preferred: getSystemDefaultDevice())
            ) ?? 0
        case .custom:
            return VoiceInkAudioInputSelectionPolicy.currentDeviceID(
                inputMode: inputMode,
                selectedDeviceID: selectedDeviceID,
                selectedDeviceIsAvailable: selectedDeviceIsAvailable,
                priorityDeviceID: nil,
                automaticDeviceID: selectedDeviceIsAvailable ? nil : findBestAvailableDevice()
            ) ?? 0
        case .prioritized:
            let priorityDeviceID = firstAvailablePriorityDevice()?.id
            return VoiceInkAudioInputSelectionPolicy.currentDeviceID(
                inputMode: inputMode,
                selectedDeviceID: selectedDeviceID,
                selectedDeviceIsAvailable: selectedDeviceIsAvailable,
                priorityDeviceID: priorityDeviceID,
                automaticDeviceID: priorityDeviceID == nil ? findBestAvailableDevice() : nil
            ) ?? 0
        }
    }
    
    private func loadPrioritizedDevices() {
        prioritizedDevices = VoiceInkAudioInputPreference.prioritizedDevices()
    }
    
    func savePrioritizedDevices() {
        VoiceInkAudioInputPreference.savePrioritizedDevices(prioritizedDevices)
    }
    
    func addPrioritizedDevice(uid: String, name: String) {
        let updatedDevices = VoiceInkAudioInputPriorityPolicy.addDevice(
            uid: uid,
            name: name,
            to: prioritizedDevices
        )
        guard updatedDevices != prioritizedDevices else { return }

        prioritizedDevices = updatedDevices
        savePrioritizedDevices()
    }
    
    func removePrioritizedDevice(id: String) {
        let wasSelected = selectedDeviceID == availableDevices.first(where: { $0.uid == id })?.id
        prioritizedDevices = VoiceInkAudioInputPriorityPolicy.removeDevice(id: id, from: prioritizedDevices)
        savePrioritizedDevices()
        
        if wasSelected && inputMode == .prioritized {
            selectHighestPriorityAvailableDevice()
        }
    }
    
    func updatePriorities(devices: [VoiceInkAudioInputPriorityDevice]) {
        prioritizedDevices = VoiceInkAudioInputPriorityPolicy.reindexed(devices)
        savePrioritizedDevices()
        
        if inputMode == .prioritized {
            selectHighestPriorityAvailableDevice()
        }
        
        notifyDeviceChange()
    }
    
    private func selectHighestPriorityAvailableDevice() {
        if let priorityDevice = firstAvailablePriorityDevice() {
            selectedDeviceID = priorityDevice.id
            logger.notice("\(VoiceInkAudioInputDiagnostics.selectedPrioritizedDeviceMessage(name: priorityDevice.name), privacy: .public)")
            notifyDeviceChange()
            return
        }

        fallbackToDefaultDevice()
    }

    private func safeAutomaticDevice(preferred preferredDeviceID: AudioDeviceID? = nil) -> AudioDeviceID? {
        let selection = VoiceInkAudioInputAutomaticSelectionPolicy.selection(
            preferred: preferredDeviceID,
            devices: automaticSelectionDevices()
        )

        switch selection.reason {
        case .preferred, .builtIn:
            break
        case .safeFallback:
            if let deviceID = selection.deviceID,
               let safeDevice = availableDevices.first(where: { $0.id == deviceID }) {
                logger.warning("\(VoiceInkAudioInputDiagnostics.safeFallbackDeviceSelectedMessage(name: safeDevice.name), privacy: .public)")
            }
        case .unavailable:
            if let firstDevice = availableDevices.first {
                logger.warning("\(VoiceInkAudioInputDiagnostics.unsafeAutomaticDeviceRefusedMessage(name: firstDevice.name), privacy: .public)")
            }
        }

        return selection.deviceID
    }

    private func automaticSelectionDevices() -> [VoiceInkAudioInputAutomaticDevice<AudioDeviceID>] {
        availableDevices.map { device in
            VoiceInkAudioInputAutomaticDevice(
                id: device.id,
                name: device.name,
                isBuiltIn: isBuiltInDevice(device.id),
                isBluetooth: isBluetoothDevice(device.id)
            )
        }
    }

    private var selectedDeviceIsAvailable: Bool {
        selectedDeviceID.map { isDeviceAvailable($0) } ?? false
    }

    private func availableSelectionDevices() -> [VoiceInkAudioInputAvailableDevice<AudioDeviceID>] {
        availableDevices.map { device in
            VoiceInkAudioInputAvailableDevice(id: device.id, uid: device.uid, name: device.name)
        }
    }

    private func firstAvailablePriorityDevice() -> VoiceInkAudioInputAvailableDevice<AudioDeviceID>? {
        VoiceInkAudioInputPriorityPolicy.firstAvailablePriorityDevice(
            in: prioritizedDevices,
            availableDevices: availableSelectionDevices()
        )
    }

    private func deviceIDToSelectWhenChangingMode(_ mode: VoiceInkAudioInputMode) -> AudioDeviceID? {
        guard selectedDeviceID == nil else { return nil }

        let priorityDeviceID = mode == .prioritized ? firstAvailablePriorityDevice()?.id : nil
        let automaticDeviceID = mode != .systemDefault && priorityDeviceID == nil ? findBestAvailableDevice() : nil

        return VoiceInkAudioInputSelectionPolicy.deviceIDToSelectWhenChangingMode(
            inputMode: mode,
            selectedDeviceID: selectedDeviceID,
            priorityDeviceID: priorityDeviceID,
            automaticDeviceID: automaticDeviceID
        )
    }

    private func isBluetoothDevice(_ deviceID: AudioDeviceID) -> Bool {
        let transportType = getTransportType(deviceID: deviceID)
        return transportType == kAudioDeviceTransportTypeBluetooth ||
            transportType == kAudioDeviceTransportTypeBluetoothLE
    }
    
    private func setupDeviceChangeNotifications() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let systemObjectID = AudioObjectID(kAudioObjectSystemObject)
        
        let status = AudioObjectAddPropertyListener(
            systemObjectID,
            &address,
            { (_, _, _, userData) -> OSStatus in
                let manager = Unmanaged<AudioDeviceManager>.fromOpaque(userData!).takeUnretainedValue()
                DispatchQueue.main.async {
                    manager.handleDeviceListChange()
                }
                return noErr
            },
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        )
        
        if status != noErr {
            logger.error("\(VoiceInkAudioInputDiagnostics.deviceChangeListenerAddFailedMessage(status: status), privacy: .public)")
        }
    }
    
    private func handleDeviceListChange() {
        logger.notice("\(VoiceInkAudioInputDiagnostics.deviceListChangeDetectedMessage, privacy: .public)")

        loadAvailableDevices { [weak self] in
            guard let self = self else { return }

            if self.inputMode == .systemDefault {
                self.notifyDeviceChange()
                return
            }

            if self.isRecordingActive {
                guard let currentID = self.selectedDeviceID else { return }

                if !self.isDeviceAvailable(currentID) {
                    self.logger.warning("\(VoiceInkAudioInputDiagnostics.recordingDeviceUnavailableMessage(deviceID: currentID), privacy: .public)")

                    let priorityDeviceID = self.inputMode == .prioritized ? self.firstAvailablePriorityDevice()?.id : nil
                    if self.inputMode == .prioritized && priorityDeviceID == nil {
                        self.logger.warning("\(VoiceInkAudioInputDiagnostics.noPriorityDevicesAvailableFallbackMessage, privacy: .public)")
                    }
                    let automaticDeviceID = priorityDeviceID == nil ? self.findBestAvailableDevice() : nil
                    let switchPlan = VoiceInkAudioInputSelectionPolicy.recordingSwitchPlan(
                        inputMode: self.inputMode,
                        priorityDeviceID: priorityDeviceID,
                        automaticDeviceID: automaticDeviceID
                    )

                    if let deviceID = switchPlan.deviceID {
                        self.selectedDeviceID = deviceID
                        NotificationCenter.default.post(
                            name: .audioDeviceSwitchRequired,
                            object: nil,
                            userInfo: VoiceInkMacOSAudioDeviceChangeRequest.switchRequiredUserInfo(deviceID: deviceID)
                        )
                    } else {
                        self.logger.error("\(VoiceInkAudioInputDiagnostics.noAudioInputDevicesAvailableMessage, privacy: .public)")
                        NotificationCenter.default.post(name: .toggleMiniRecorder, object: nil)
                    }
                }
                return
            }

            if self.inputMode == .prioritized {
                self.selectHighestPriorityAvailableDevice()
            } else if self.inputMode == .custom,
                      let currentID = self.selectedDeviceID,
                      !self.isDeviceAvailable(currentID) {
                self.fallbackToDefaultDevice()
            }
        }
    }
    
    private func getDeviceUID(deviceID: AudioDeviceID) -> String? {
        let uid: CFString? = getDeviceProperty(deviceID: deviceID,
                                             selector: kAudioDevicePropertyDeviceUID)
        return uid as String?
    }
    
    deinit {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        AudioObjectRemovePropertyListener(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            { (_, _, _, userData) -> OSStatus in
                return noErr
            },
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        )
    }
    
    private func createPropertyAddress(selector: AudioObjectPropertySelector,
                                    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                                    element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
        return AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: element
        )
    }
    
    private func getDeviceProperty<T>(deviceID: AudioDeviceID,
                                    selector: AudioObjectPropertySelector,
                                    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> T? {
        guard deviceID != 0 else { return nil }
        
        var address = createPropertyAddress(selector: selector, scope: scope)
        var propertySize = UInt32(MemoryLayout<T>.size)
        var property: T? = nil
        
        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &propertySize,
            &property
        )
        
        if status != noErr {
            logger.error("\(VoiceInkAudioInputDiagnostics.devicePropertyLookupFailedMessage(selector: selector, deviceID: deviceID, status: status), privacy: .public)")
            return nil
        }
        
        return property
    }

    private func getTransportType(deviceID: AudioDeviceID) -> UInt32? {
        var address = createPropertyAddress(selector: kAudioDevicePropertyTransportType)
        var propertySize = UInt32(MemoryLayout<UInt32>.size)
        var transportType: UInt32 = 0

        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &propertySize,
            &transportType
        )

        if status != noErr {
            logger.error("\(VoiceInkAudioInputDiagnostics.transportTypeLookupFailedMessage(deviceID: deviceID, status: status), privacy: .public)")
            return nil
        }

        return transportType
    }
    
    private func notifyDeviceChange() {
        NotificationCenter.default.post(name: .audioDeviceChanged, object: nil)
    }
} 
