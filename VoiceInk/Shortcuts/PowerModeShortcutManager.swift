import Foundation
import VoiceInkCore

@MainActor
class PowerModeShortcutManager {
    private let shortcutMonitor = ShortcutMonitor()
    private let modeProvider: @MainActor () -> RecordingShortcutManager.Mode
    private let specialOptionsProvider: @MainActor () -> SpecialShortcutOptions
    private let shortcutModeHandler: RecordingShortcutModeHandler
    private var shortcutChangeObserver: NSObjectProtocol?

    init(
        modeProvider: @escaping @MainActor () -> RecordingShortcutManager.Mode,
        specialOptionsProvider: @escaping @MainActor () -> SpecialShortcutOptions,
        shortcutModeHandler: RecordingShortcutModeHandler
    ) {
        self.modeProvider = modeProvider
        self.specialOptionsProvider = specialOptionsProvider
        self.shortcutModeHandler = shortcutModeHandler

        refreshPowerModeShortcuts()

        shortcutChangeObserver = NotificationCenter.default.addObserver(
            forName: ShortcutStore.shortcutDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard
                let action = notification.object as? ShortcutAction,
                case .powerMode = action
            else {
                return
            }

            Task { @MainActor in
                self?.refreshPowerModeShortcuts()
            }
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(powerModeShortcutAvailabilityDidChange),
            name: .powerModeShortcutAvailabilityDidChange,
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        if let shortcutChangeObserver {
            NotificationCenter.default.removeObserver(shortcutChangeObserver)
        }
        MainActor.assumeIsolated {
            shortcutMonitor.stop()
        }
    }

    @objc private func powerModeShortcutAvailabilityDidChange() {
        Task { @MainActor in
            refreshPowerModeShortcuts()
        }
    }

    private func refreshPowerModeShortcuts() {
        guard VoiceInkPowerModePreference.isUIEnabled() else {
            shortcutMonitor.stop()
            return
        }

        let shortcuts = PowerModeManager.shared.configurations
            .powerModeShortcutEntries { id in
                ShortcutStore.shortcut(for: .powerMode(id))
            }
            .reduce(into: [ShortcutAction: Shortcut]()) { result, entry in
                result[.powerMode(entry.configuration.id)] = entry.shortcut
            }

        let mode = modeProvider()
        shortcutMonitor.start(
            shortcuts: shortcuts,
            interruptibleActions: mode.allowsShortcutInterruption ? Set(shortcuts.keys) : [],
            tracksKeyUpEvidence: mode.tracksKeyUpEvidence,
            onKeyDown: { [weak self] action, eventTime in
                Task { @MainActor in
                    guard let self,
                          let powerModeId = self.powerModeId(for: action) else {
                        return
                    }

                    await self.shortcutModeHandler.handleKeyDown(
                        action: action,
                        eventTime: eventTime,
                        mode: self.modeProvider(),
                        specialOptions: self.specialOptionsProvider(),
                        powerModeId: powerModeId
                    )
                }
            },
            onKeyUp: { [weak self] action, eventTime, context in
                Task { @MainActor in
                    guard let self,
                          case .powerMode(let powerModeId) = action else {
                        return
                    }

                    await self.shortcutModeHandler.handleKeyUp(
                        action: action,
                        eventTime: eventTime,
                        mode: self.modeProvider(),
                        context: context,
                        specialOptions: self.specialOptionsProvider(),
                        powerModeId: powerModeId
                    )
                }
            },
            onPressContextChanged: { [weak self] action, context in
                Task { @MainActor in
                    guard let self,
                          case .powerMode = action,
                          self.modeProvider().tracksKeyUpEvidence else {
                        return
                    }
                    self.shortcutModeHandler.handlePressContextChanged(
                        action: action,
                        context: context
                    )
                }
            },
            onShortcutInterrupted: { [weak self] action, _ in
                Task { @MainActor in
                    guard let self, case .powerMode = action else { return }
                    await self.shortcutModeHandler.handleInterruption(action: action)
                }
            }
        )
    }

    private func powerModeId(for action: ShortcutAction) -> UUID? {
        guard case .powerMode(let powerModeId) = action else {
            return nil
        }

        return PowerModeManager.shared.configurations.powerModeShortcutConfigurationId(
            for: powerModeId,
            shortcutExists: { id in
                ShortcutStore.shortcut(for: .powerMode(id)) != nil
            }
        )
    }
}
