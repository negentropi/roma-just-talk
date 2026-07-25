//
//  KeyboardViewController.swift
//  VoiceInkKeyboard
//
//  Created by Prakash Joshi on 28/08/2025.
//

import UIKit
import KeyboardKit
import SwiftUI
import VoiceInkCore

class KeyboardViewController: KeyboardInputViewController {
    private static let insertDictationPresentation = VoiceInkKeyboardRecordingButtonPresentation(
        title: " Insert Dictation",
        systemImageName: "text.badge.plus"
    )
    
    var recordButton: UIButton!
    private var hideKeyboardButton: UIButton!
    private let coordinator = AppGroupCoordinator.shared
    private let shellState = VoiceInkKeyboardShellState()
    private lazy var clipboardModel = VoiceInkKeyboardClipboardModel(
        store: VoiceInkKeyboardClipboardStore.appGroupStore()
    )
    private var recordingStatusTimer: Timer?

    private var currentDocumentIdentifier: UUID? {
        guard let proxy = textDocumentProxy as? NSObject else {
            return nil
        }

        let selector = NSSelectorFromString("documentIdentifier")
        guard proxy.responds(to: selector) else {
            return nil
        }

        return VoiceInkKeyboardDocumentIdentifierPolicy.resolve(
            proxy.value(forKey: "documentIdentifier")
        )
    }
    
    deinit {
        recordingStatusTimer?.invalidate()
        recordingStatusTimer = nil
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        let standardActionHandler = services.actionHandler
        services.actionHandler = VoiceInkKeyboardActionHandler(
            standardHandler: standardActionHandler,
            keyboardContext: state.keyboardContext,
            shellState: shellState
        )
        setupShellCallbacks()
        setupRecordButton()
        setupHideKeyboardButton()
        setupRecordingStatusMonitoring()
    }

    override func viewWillSetupKeyboardView() {
        setupKeyboardView { [weak self] controller in
            let shellState = self?.shellState ?? VoiceInkKeyboardShellState()
            let clipboardModel = self?.clipboardModel ?? VoiceInkKeyboardClipboardModel(store: nil)
            return VoiceInkKeyboardShellView(
                services: controller.services,
                state: controller.state,
                shellState: shellState,
                clipboardModel: clipboardModel,
                onOpenClipboard: { [weak self] in
                    guard let self else { return }
                    self.clipboardModel.captureCurrentPasteboard(
                        hasFullAccess: self.hasFullAccess
                    )
                },
                onActivateClipboardItem: { [weak self] item in
                    self?.activateClipboardItem(item)
                }
            )
        }
    }

    private func setupShellCallbacks() {
        shellState.onSurfaceChange = { [weak self] surface in
            self?.updateChromeVisibility(for: surface)
        }
        shellState.onSubmitSearch = { [weak self] in
            self?.activateFirstClipboardSearchResult()
        }
    }
    
    private func setupRecordButton() {
        // Create the native iOS-style record button
        recordButton = UIButton(type: .system)
        recordButton.translatesAutoresizingMaskIntoConstraints = false
        recordButton.addTarget(self, action: #selector(recordButtonTapped), for: .touchUpInside)
        recordButton.accessibilityIdentifier = "voiceink.keyboard.record"
        
        // Configure for idle state initially
        configureButton(
            VoiceInkKeyboardRecordingButtonPresentation.idle,
            backgroundColor: .systemBlue
        )
        
        // Add native iOS styling
        recordButton.titleLabel?.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
        recordButton.contentEdgeInsets = UIEdgeInsets(top: 6, left: 16, bottom: 6, right: 16)
        
        // Native iOS shadow and styling
        recordButton.layer.shadowColor = UIColor.black.cgColor
        recordButton.layer.shadowOffset = CGSize(width: 0, height: 1)
        recordButton.layer.shadowOpacity = 0.2
        recordButton.layer.shadowRadius = 2
        
        // Add subtle border for better definition
        recordButton.layer.borderWidth = 0.5
        recordButton.layer.borderColor = UIColor.separator.cgColor
        
        // Add button to main view
        view.addSubview(recordButton)
        
        // Set up constraints - position in top center with safe margins
        NSLayoutConstraint.activate([
            recordButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            recordButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 6),
            recordButton.heightAnchor.constraint(equalToConstant: 32),
            recordButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 120)
        ])
        
        // Ensure button stays on top
        view.bringSubviewToFront(recordButton)
    }

    private func setupHideKeyboardButton() {
        hideKeyboardButton = UIButton(type: .system)
        hideKeyboardButton.translatesAutoresizingMaskIntoConstraints = false
        hideKeyboardButton.addTarget(
            self,
            action: #selector(hideKeyboardButtonTapped),
            for: .touchUpInside
        )
        hideKeyboardButton.setImage(
            UIImage(systemName: "keyboard.chevron.compact.down"),
            for: .normal
        )
        hideKeyboardButton.tintColor = .label
        hideKeyboardButton.backgroundColor = .secondarySystemBackground
        hideKeyboardButton.layer.cornerRadius = 16
        hideKeyboardButton.layer.borderWidth = 0.5
        hideKeyboardButton.layer.borderColor = UIColor.separator.cgColor
        hideKeyboardButton.accessibilityLabel = "Hide Keyboard"
        hideKeyboardButton.accessibilityIdentifier = "voiceink.keyboard.hide"

        view.addSubview(hideKeyboardButton)
        NSLayoutConstraint.activate([
            hideKeyboardButton.trailingAnchor.constraint(
                equalTo: recordButton.leadingAnchor,
                constant: -8
            ),
            hideKeyboardButton.centerYAnchor.constraint(equalTo: recordButton.centerYAnchor),
            hideKeyboardButton.widthAnchor.constraint(equalToConstant: 32),
            hideKeyboardButton.heightAnchor.constraint(equalToConstant: 32)
        ])
        view.bringSubviewToFront(hideKeyboardButton)
    }
    
    private func configureButton(
        _ presentation: VoiceInkKeyboardRecordingButtonPresentation,
        backgroundColor: UIColor,
        isEnabled: Bool = true
    ) {
        let imageConfig = UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        let image = UIImage(systemName: presentation.systemImageName, withConfiguration: imageConfig)

        recordButton.setImage(image, for: .normal)
        recordButton.setTitle(presentation.title, for: .normal)
        recordButton.backgroundColor = backgroundColor
        recordButton.setTitleColor(.white, for: .normal)
        recordButton.tintColor = .white
        recordButton.isEnabled = isEnabled
        recordButton.alpha = isEnabled ? 1 : 0.75

        recordButton.semanticContentAttribute = .forceLeftToRight
        recordButton.imageEdgeInsets = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 4)
        recordButton.titleEdgeInsets = UIEdgeInsets(top: 0, left: 4, bottom: 0, right: 0)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        coordinator.reportKeyboardReadiness(hasFullAccess: hasFullAccess)
        updateButtonAppearanceBasedOnState()
        restoreChromeButtonsIfNeeded()

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.recordButton.layer.cornerRadius = self.recordButton.frame.height / 2
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        restoreChromeButtonsIfNeeded()
        recordButton.layer.cornerRadius = recordButton.frame.height / 2
    }

    private func restoreChromeButtonsIfNeeded() {
        for button in [hideKeyboardButton, recordButton].compactMap({ $0 }) {
            if button.superview == nil {
                view.addSubview(button)
            }
            view.bringSubviewToFront(button)
        }
        updateChromeVisibility(for: shellState.surface)
    }

    private func updateChromeVisibility(for surface: VoiceInkKeyboardShellState.Surface) {
        recordButton?.isHidden = surface == .clipboard
    }

    @objc private func hideKeyboardButtonTapped() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        dismissKeyboard()
    }

    private func activateFirstClipboardSearchResult() {
        guard let item = clipboardModel.filteredItems(
            matching: shellState.clipboardQuery,
            filter: shellState.clipboardFilter
        ).first else {
            return
        }
        activateClipboardItem(item)
    }

    private func activateClipboardItem(_ item: VoiceInkKeyboardClipboardItem) {
        switch item.kind {
        case .text, .link:
            guard let text = item.text, !text.isEmpty else { return }
            textDocumentProxy.insertText(text)
            clipboardModel.markUsed(item)
            shellState.showKeyboard()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .image:
            guard hasFullAccess,
                  let image = clipboardModel.image(for: item) else {
                return
            }
            UIPasteboard.general.image = image
            clipboardModel.markUsed(item)
            clipboardModel.reportImageCopied()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }
    
    @objc private func recordButtonTapped() {
        // Add native iOS button press animation
        addButtonPressAnimation()
        
        // Provide haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()

        guard hasFullAccess else {
            coordinator.reportKeyboardReadiness(hasFullAccess: false)
            updateButtonAppearanceBasedOnState()
            return
        }
        
        let isRecording = coordinator.isRecording
        if !isRecording {
            if deliverCompletedDictationIfAvailable() {
                updateButtonAppearanceBasedOnState()
                return
            }

            if let documentIdentifier = currentDocumentIdentifier {
                switch keyboardDictationStatus(for: documentIdentifier) {
                case .requested, .ready, .waitingForOriginalDocument:
                    return
                case .readyForManualInsertion:
                    _ = deliverCompletedDictationIfAvailable(confirmDocumentChange: true)
                    updateButtonAppearanceBasedOnState()
                    return
                case .failed(let requestID, _):
                    coordinator.clearKeyboardDictation(requestID: requestID)
                case .none:
                    break
                }
            }
        }

        let tapPlan = VoiceInkKeyboardRecordingButtonTapPolicy.plan(isRecording: isRecording)

        tapPlan.applyRuntimeState(
            requestStopRecording: coordinator.requestStopRecording,
            openMainAppForRecording: { [weak self] in
                guard let self = self else { return }
                guard let documentIdentifier = self.currentDocumentIdentifier else {
                    self.updateButtonAppearanceBasedOnState()
                    return
                }
                guard let requestID = self.coordinator.beginKeyboardDictation(
                    documentIdentifier: documentIdentifier,
                    surroundingTextBeforeCursor: self.textDocumentProxy.documentContextBeforeInput,
                    surroundingTextAfterCursor: self.textDocumentProxy.documentContextAfterInput
                ) else {
                    self.updateButtonAppearanceBasedOnState()
                    return
                }

                VoiceInkKeyboardURLOpener.openMainApp(
                    url: VoiceInkAppDeepLink.record.url,
                    extensionContext: self.extensionContext,
                    responder: self,
                    fallback: { [weak self] in
                        self?.coordinator.clearKeyboardDictation(requestID: requestID)
                        self?.showUserMessage()
                    }
                )
            },
            refreshButtonState: updateButtonAppearanceBasedOnState
        )
    }
    
    private func addButtonPressAnimation() {
        // Native iOS button press animation - scale down then back up
        UIView.animate(withDuration: 0.1, delay: 0, options: [.curveEaseInOut], animations: {
            self.recordButton.transform = CGAffineTransform(scaleX: 0.95, y: 0.95)
        }) { _ in
            UIView.animate(withDuration: 0.1, delay: 0, options: [.curveEaseInOut], animations: {
                self.recordButton.transform = CGAffineTransform.identity
            })
        }
    }
    
    private func showUserMessage() {
        // Last resort: Update button to show user should open main app manually
        configureButton(
            VoiceInkKeyboardRecordingButtonPresentation.openAppFallback,
            backgroundColor: .systemOrange
        )
        
        DispatchQueue.main.asyncAfter(deadline: .now() + VoiceInkKeyboardRecordingTiming.openAppFallbackResetDelay) {
            self.configureButton(
                VoiceInkKeyboardRecordingButtonPresentation.idle,
                backgroundColor: .systemBlue
            )
        }
    }
    
    private func setupRecordingStatusMonitoring() {
        recordingStatusTimer = Timer.scheduledTimer(
            withTimeInterval: VoiceInkKeyboardRecordingTiming.recordingStatusPollingInterval,
            repeats: true
        ) { [weak self] _ in
            self?.updateButtonAppearanceBasedOnState()
        }
        
        // Initial state update
        updateButtonAppearanceBasedOnState()
    }
    
    private func updateButtonAppearanceBasedOnState() {
        _ = deliverCompletedDictationIfAvailable()

        let isRecording = coordinator.isRecording
        let presentation: VoiceInkKeyboardRecordingButtonPresentation
        let backgroundColor: UIColor
        let isEnabled: Bool

        if !hasFullAccess {
            presentation = .fullAccessRequired
            backgroundColor = .systemOrange
            isEnabled = false
        } else if let documentIdentifier = currentDocumentIdentifier {
            switch keyboardDictationStatus(for: documentIdentifier) {
            case .none:
                presentation = .current(isRecording: isRecording)
                backgroundColor = isRecording ? .systemRed : .systemBlue
                isEnabled = true
            case .requested, .ready:
                presentation = isRecording ? .recording : .transcribing
                backgroundColor = isRecording ? .systemRed : .systemGray
                isEnabled = isRecording
            case .readyForManualInsertion:
                presentation = Self.insertDictationPresentation
                backgroundColor = .systemBlue
                isEnabled = true
            case .failed:
                presentation = .transcriptionFailed
                backgroundColor = .systemOrange
                isEnabled = true
            case .waitingForOriginalDocument:
                presentation = .returnToOriginalField
                backgroundColor = .systemOrange
                isEnabled = false
            }
        } else {
            presentation = .idle
            backgroundColor = .systemGray
            isEnabled = false
        }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let button = self.recordButton else { return }
            
            self.configureButton(
                presentation,
                backgroundColor: backgroundColor,
                isEnabled: isEnabled
            )
            
            // Ensure capsule shape is maintained
            button.layer.cornerRadius = button.frame.height / 2
        }
    }

    private func keyboardDictationStatus(
        for documentIdentifier: UUID
    ) -> VoiceInkKeyboardDictationExchangeStatus {
        coordinator.keyboardDictationStatus(
            documentIdentifier: documentIdentifier,
            surroundingTextBeforeCursor: textDocumentProxy.documentContextBeforeInput,
            surroundingTextAfterCursor: textDocumentProxy.documentContextAfterInput
        )
    }

    @discardableResult
    private func deliverCompletedDictationIfAvailable(
        confirmDocumentChange: Bool = false
    ) -> Bool {
        guard let documentIdentifier = currentDocumentIdentifier else {
            return false
        }

        let contextBeforeCursor = textDocumentProxy.documentContextBeforeInput
        guard let delivery = coordinator.takeCompletedKeyboardDictation(
            documentIdentifier: documentIdentifier,
            surroundingTextBeforeCursor: contextBeforeCursor,
            surroundingTextAfterCursor: textDocumentProxy.documentContextAfterInput,
            confirmDocumentChange: confirmDocumentChange
        ) else {
            return false
        }

        let plan = VoiceInkIOSKeyboardDeliveryPolicy.plan(
            text: delivery.text,
            shouldLowercase: delivery.shouldLowercase,
            shouldInsertReturn: delivery.shouldInsertReturn,
            beforeCursor: VoiceInkCursorTextContextPolicy.boundedSuffix(
                contextBeforeCursor
            )
        )
        textDocumentProxy.insertText(plan.text)
        if plan.shouldInsertReturn {
            textDocumentProxy.insertText(VoiceInkIOSKeyboardDeliveryPolicy.returnText)
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        return true
    }
    
    override func textWillChange(_ textInput: UITextInput?) {
        // The app is about to change the document's contents
        super.textWillChange(textInput)
    }
    
    override func textDidChange(_ textInput: UITextInput?) {
        // The app has just changed the document's contents
        super.textDidChange(textInput)
        updateButtonAppearanceBasedOnState()
    }
}
