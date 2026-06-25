//
//  KeyboardViewController.swift
//  VoiceInkKeyboard
//
//  Created by Prakash Joshi on 28/08/2025.
//

import UIKit
import KeyboardKit
import VoiceInkCore

class KeyboardViewController: KeyboardInputViewController {
    
    var recordButton: UIButton!
    private let coordinator = AppGroupCoordinator.shared
    private var recordingStatusTimer: Timer?
    
    deinit {
        recordingStatusTimer?.invalidate()
        recordingStatusTimer = nil
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupRecordButton()
        setupRecordingStatusMonitoring()
    }
    
    private func setupRecordButton() {
        // Create the native iOS-style record button
        recordButton = UIButton(type: .system)
        recordButton.translatesAutoresizingMaskIntoConstraints = false
        recordButton.addTarget(self, action: #selector(recordButtonTapped), for: .touchUpInside)
        
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
    
    private func configureButton(
        _ presentation: VoiceInkKeyboardRecordingButtonPresentation,
        backgroundColor: UIColor
    ) {
        let imageConfig = UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        let image = UIImage(systemName: presentation.systemImageName, withConfiguration: imageConfig)

        recordButton.setImage(image, for: .normal)
        recordButton.setTitle(presentation.title, for: .normal)
        recordButton.backgroundColor = backgroundColor
        recordButton.setTitleColor(.white, for: .normal)
        recordButton.tintColor = .white

        recordButton.semanticContentAttribute = .forceLeftToRight
        recordButton.imageEdgeInsets = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 4)
        recordButton.titleEdgeInsets = UIEdgeInsets(top: 0, left: 4, bottom: 0, right: 0)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        // Re-add and ensure record button stays on top after KeyboardKit layout
        if let button = recordButton {
            if button.superview == nil {
                view.addSubview(button)
            }
            view.bringSubviewToFront(button)
            
            // Ensure proper capsule shape after layout
            DispatchQueue.main.async {
                button.layer.cornerRadius = button.frame.height / 2
            }
        }
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        // Re-add button if KeyboardKit removed it
        if let button = recordButton, button.superview == nil {
            view.addSubview(button)
        }
        
        // Ensure button is still visible after layout
        if let button = recordButton {
            view.bringSubviewToFront(button)
            
            // Make button fully capsule-shaped based on its actual height
            button.layer.cornerRadius = button.frame.height / 2
        }
    }
    
    @objc private func recordButtonTapped() {
        // Add native iOS button press animation
        addButtonPressAnimation()
        
        // Provide haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
        
        let tapPlan = VoiceInkKeyboardRecordingButtonTapPolicy.plan(
            isRecording: coordinator.isRecording
        )

        tapPlan.applyRuntimeState(
            requestStopRecording: coordinator.requestStopRecording,
            openMainAppForRecording: openMainAppForRecording,
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
    
    private func openMainAppForRecording() {
        VoiceInkKeyboardURLOpener.openMainApp(
            url: VoiceInkAppDeepLink.record.url,
            extensionContext: extensionContext,
            responder: self,
            fallback: { [weak self] in
                self?.showUserMessage()
            }
        )
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
        let presentation = VoiceInkKeyboardRecordingButtonPresentation.current(
            isRecording: coordinator.isRecording
        )
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let button = self.recordButton else { return }
            
            self.configureButton(
                presentation,
                backgroundColor: presentation == .recording ? .systemRed : .systemBlue
            )
            
            // Ensure capsule shape is maintained
            button.layer.cornerRadius = button.frame.height / 2
        }
    }
    
    override func textWillChange(_ textInput: UITextInput?) {
        // The app is about to change the document's contents
        super.textWillChange(textInput)
    }
    
    override func textDidChange(_ textInput: UITextInput?) {
        // The app has just changed the document's contents
        super.textDidChange(textInput)
    }
}
