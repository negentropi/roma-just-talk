// TEST ONLY. Drives the unchanged production language picker on a disposable hosted Mac.
#if !LOCAL_BUILD
#error("LanguageSelectionProbeOracle requires LOCAL_BUILD.")
#endif

import AppKit
import Darwin
import Foundation
import VoiceInkCore

private struct LanguageSelectionProbeFailure: Error, CustomStringConvertible {
    let description: String
    init(_ message: String) { description = message }
}

@MainActor
enum LanguageSelectionProbeOracle {
    static func run(owner: LanguageSelectionProbeOwner) async {
        let check = Check(owner: owner)
        do {
            let persisted = try await check.execute()
            try check.finish(classification: persisted ? "passed" : "same-selection-not-persisted", exitCode: persisted ? 0 : 1, failure: nil)
            Darwin.exit(persisted ? 0 : 1)
        } catch {
            try? check.dumpHierarchy("invalid")
            try? await check.screenshot("invalid")
            try? check.finish(classification: "invalid", exitCode: 2, failure: String(describing: error))
            fputs("Language selection probe invalid: \(error)\n", stderr)
            Darwin.exit(2)
        }
    }

    @MainActor
    private final class Check {
        let owner: LanguageSelectionProbeOwner
        let app = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        let languageKey = VoiceInkUserDefaultsKey.selectedTranscriptionLanguage
        let input = "Um, send it tomorrow."
        let cleaned = "send it tomorrow."
        let selectedCases = ["same-current-english", "changed-japanese", "changed-english"]
        let deadline = ProcessInfo.processInfo.systemUptime + 90
        var baseline: [String: Any] = [:]
        var cases: [[String: Any]] = []
        var environment: [String: Any] = [:]
        var model: [String: Any] = [:]
        var primaryPersisted: Bool?
        var positiveControlsPassed = false
        var window: AXUIElement?
        var picker: AXUIElement?
        var englishLabel = ""
        var japaneseLabel = ""

        init(owner: LanguageSelectionProbeOwner) { self.owner = owner }

        func execute() async throws -> Bool {
            try require(AXIsProcessTrusted(), "The exact host lacks Accessibility access.")
            try require(CGPreflightScreenCaptureAccess(), "The exact host lacks Screen Recording access.")
            let expectedHome = ProcessInfo.processInfo.environment["CFFIXED_USER_HOME"] ?? ""
            let observedHome = NSHomeDirectory()
            let arguments = Array(ProcessInfo.processInfo.arguments.dropFirst())
            let homeMatches = !expectedHome.isEmpty && URL(fileURLWithPath: expectedHome).standardizedFileURL == URL(fileURLWithPath: observedHome).standardizedFileURL
            environment = ["expectedUserHome": expectedHome, "observedUserHome": observedHome,
                           "homeMatchesExpected": homeMatches, "arguments": arguments,
                           "hasLanguageArgumentOverride": UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)[languageKey] != nil]
            try require(Bundle.main.bundleIdentifier == "com.negentropi.RomaJustTalk" && homeMatches && arguments.isEmpty,
                        "Expected the exact isolated host with no command-line preference overrides.")
            try require(UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)[languageKey] == nil,
                        "SelectedLanguage has an argument-domain override.")
            guard let actual = owner.transcriptionModelManager.currentTranscriptionModel else {
                throw LanguageSelectionProbeFailure("The real model manager has no selected model.")
            }
            let facts = actual.transcriptionLanguageSelectionFacts
            englishLabel = facts.languageOptions["en"] ?? ""
            japaneseLabel = facts.languageOptions["ja"] ?? ""
            model = ["name": actual.name, "provider": actual.provider.rawValue,
                     "isMultilingual": actual.isMultilingualModel, "shouldShowPicker": facts.shouldShowPicker,
                     "englishLabel": englishLabel, "japaneseLabel": japaneseLabel,
                     "modelLoaded": owner.whisperModelManager.isModelLoaded,
                     "contextAbsent": owner.whisperModelManager.whisperContext == nil,
                     "availableModelCount": owner.whisperModelManager.availableModels.count]
            try require(actual.name == "ggml-tiny" && actual.provider == .whisper && actual.isMultilingualModel
                        && facts.shouldShowPicker && !facts.showsNativeAppleAssetControl
                        && !englishLabel.isEmpty && !japaneseLabel.isEmpty
                        && owner.whisperModelManager.whisperContext == nil && !owner.whisperModelManager.isModelLoaded
                        && owner.whisperModelManager.availableModels.isEmpty,
                        "Expected an unloaded real multilingual ggml-tiny registry model and its en/ja picker facts.")
            try await wait("The actual probe window did not appear.") {
                NSApp.windows.filter { $0.title == "RJT language selection probe" && $0.isVisible }.count == 1
            }
            guard let nativeWindow = NSApp.windows.first(where: { $0.title == "RJT language selection probe" && $0.isVisible }) else {
                throw LanguageSelectionProbeFailure("The exact probe window is missing.")
            }
            NSApp.activate(ignoringOtherApps: true)
            nativeWindow.makeKeyAndOrderFront(nil)
            try await wait("The actual probe window did not become key.") { NSApp.isActive && nativeWindow.isKeyWindow }
            window = try await unique("Expected one accessible probe window.") { node in
                self.string(kAXRoleAttribute, node) == kAXWindowRole && self.string(kAXTitleAttribute, node) == "RJT language selection probe"
            }
            picker = try await findPicker(displaying: englishLabel)
            // Check again after mounting: @AppStorage initialization cannot count as an explicit choice.
            try await Task.sleep(for: .milliseconds(250))
            baseline = ["preferences": preferenceSnapshot()]
            baseline = try await snapshot(expectedOutput: input)
            try require(language(in: baseline, domain: "persistent") == nil
                        && type(in: baseline, domain: "persistent") == "missing"
                        && language(in: baseline, domain: "registered") == "en"
                        && language(in: baseline, domain: "effective") == "en"
                        && type(in: baseline, domain: "argument") == "missing",
                        "After the real view mounted, English must be registered/effective while persistent and argument values remain absent.")
            try dumpHierarchy("baseline")
            try await screenshot("baseline")

            let primary = try await select(code: "en", label: englishLabel, id: selectedCases[0], wasCurrent: true, before: baseline)
            let persisted = language(in: primary, domain: "persistent") == "en"
            try require(persisted || type(in: primary, domain: "persistent") == "missing",
                        "Same-current English produced an unexpected persistent value or type.")
            primaryPersisted = persisted
            let japanese = try await select(code: "ja", label: japaneseLabel, id: selectedCases[1], wasCurrent: false, before: primary)
            try require(language(in: japanese, domain: "persistent") == "ja", "The changed Japanese positive control did not persist ja.")
            let english = try await select(code: "en", label: englishLabel, id: selectedCases[2], wasCurrent: false, before: japanese)
            try require(language(in: english, domain: "persistent") == "en", "The changed English positive control did not persist en.")
            positiveControlsPassed = true
            return persisted
        }

        func select(code: String, label: String, id: String, wasCurrent: Bool, before: [String: Any]) async throws -> [String: Any] {
            try require(ProcessInfo.processInfo.systemUptime < deadline, "The probe exceeded its total deadline.")
            let index = cases.count
            cases.append(["id": id, "requestedCode": code, "requestedLabel": label,
                          "wasCurrent": wasCurrent, "before": before, "completed": false])
            guard let picker else { throw LanguageSelectionProbeFailure("The captured actual picker is missing.") }
            let beforeControl = try describe(picker)
            cases[index]["action"] = ["pickerBefore": beforeControl]
            try require(isWindowStillCurrent() && enabled(picker), "The actual picker window or control changed.")
            try require(controlDisplays(picker, label: label) == wasCurrent,
                        "The actual picker selection does not match this case's current/changed precondition.")
            try press(picker)
            let menu = try await unique("Expected one opened picker menu containing the requested language.") { node in
                self.string(kAXRoleAttribute, node) == kAXMenuRole && self.children(node).contains {
                    self.string(kAXRoleAttribute, $0) == kAXMenuItemRole && self.string(kAXTitleAttribute, $0) == label
                }
            }
            let matches = children(menu).filter { string(kAXRoleAttribute, $0) == kAXMenuItemRole && string(kAXTitleAttribute, $0) == label }
            try require(matches.count == 1, "The actual open picker menu does not contain exactly one requested item.")
            let item = matches[0]
            let itemBefore = try describe(item)
            let checked = checkedEvidence(item)
            let menuIsPickerDescendant = try nodes(root: picker).contains { CFEqual($0, menu) }
            var action: [String: Any] = ["pickerBefore": beforeControl, "menuItemBefore": itemBefore,
                                         "menuCheckedEvidence": checked, "menuBefore": try describe(menu),
                                         "menuIsPickerDescendant": menuIsPickerDescendant]
            cases[index]["action"] = action
            try require(menuIsPickerDescendant, "The opened language menu is not an observed descendant of the actual picker.")
            try require(hasVisibleFrame(item) && enabled(item), "The requested actual language menu item is not visible and enabled.")
            if wasCurrent {
                try require(isChecked(item), "The primary English item was not observably the current checked selection.")
            } else {
                try require(!isChecked(item), "The changed-selection control unexpectedly targets the current checked item.")
            }
            try dumpHierarchy(id + "-menu")
            try await screenshot(id + "-menu")
            // One AXPress on the actual menu item. Never call the private setter or write the preference here.
            try press(item)
            action["pressAXError"] = AXError.success.rawValue
            cases[index]["action"] = action
            try await wait("The actual language picker menu did not dismiss after selection.") {
                !self.hasVisibleFrame(menu) || self.string(kAXRoleAttribute, menu) == nil
            }
            action["menuDismissed"] = true
            let expectedLabel = label
            try await wait("The actual picker did not display the requested language.") { self.controlDisplays(picker, label: expectedLabel) }
            if wasCurrent {
                // Allow asynchronous AppStorage propagation; missing after this bounded observation is the measured outcome.
                let observationEnd = ProcessInfo.processInfo.systemUptime + 1
                while ProcessInfo.processInfo.systemUptime < observationEnd {
                    _ = UserDefaults.standard.synchronize()
                    if persistentLanguage() == "en" { break }
                    try await Task.sleep(for: .milliseconds(30))
                }
            } else {
                try await wait("The changed-selection control did not persist its exact code.") {
                    _ = UserDefaults.standard.synchronize()
                    return self.persistentLanguage() == code
                }
            }
            let expectedOutput = persistentLanguage() == "en" ? cleaned : input
            cases[index]["after"] = ["preferences": preferenceSnapshot()]
            let after = try await snapshot(expectedOutput: expectedOutput)
            try require(language(in: after, domain: "effective") == code
                        && type(in: after, domain: "argument") == "missing"
                        && language(in: after, domain: "registered") == "en",
                        "Selection changed the effective language or its isolated preference domains unexpectedly.")
            action["pickerAfter"] = try describe(picker)
            cases[index]["action"] = action
            cases[index]["after"] = after
            cases[index]["completed"] = true
            cases[index]["passed"] = !wasCurrent || language(in: after, domain: "persistent") == "en"
            try dumpHierarchy(id + "-after")
            try await screenshot(id + "-after")
            return after
        }

        func snapshot(expectedOutput: String) async throws -> [String: Any] {
            _ = UserDefaults.standard.synchronize()
            let preferences = preferenceSnapshot()
            guard let persistent = preferences["persistent"] as? [String: Any],
                  let cfPersistent = preferences["cfPersistent"] as? [String: Any] else {
                throw LanguageSelectionProbeFailure("Persistent-domain observations are missing.")
            }
            try require(preferences["cfSynchronizeSucceeded"] as? Bool == true
                        && persistent["type"] as? String == cfPersistent["type"] as? String
                        && persistent["value"] as? String == cfPersistent["value"] as? String,
                        "UserDefaults and exact Core Foundation persistent domains disagree.")
            let plan = DictationPostprocessingPlan.capture(profile: .light, using: owner.context, enhancementService: nil)
            guard case .light(let light) = plan else { throw LanguageSelectionProbeFailure("Fresh capture did not produce a Light plan.") }
            let rules = try light.libraries.replacementRules.get()
            try require(light.libraries.snippets.isEmpty && rules.isEmpty, "The fresh Light capture contains a nonempty library.")
            let observedLanguage = (preferences["persistent"] as? [String: Any])?["value"] as? String
            try require(light.storedLanguage == observedLanguage,
                        "The fresh Light capture did not use the observed persistent language.")
            guard let output = try await plan.process(recognitionText: input, using: nil) else {
                throw LanguageSelectionProbeFailure("The fresh Light plan produced no output.")
            }
            try require(output.literalOutput.utf16.elementsEqual(expectedOutput.utf16)
                        && output.recognitionText.utf16.elementsEqual(input.utf16)
                        && output.preparedText.utf16.elementsEqual(expectedOutput.utf16)
                        && output.enhancementResult == nil && output.fallbackReason == nil,
                        "Fresh Light processing did not match the observed explicit-language state.")
            return ["preferences": preferences,
                    "light": ["capturedLanguage": typed(light.storedLanguage as Any?), "input": input,
                              "output": output.literalOutput, "recognitionText": output.recognitionText,
                              "preparedText": output.preparedText, "emptySnippets": true,
                              "emptyReplacementRules": true, "noEnhancement": true, "noFallback": true]]
        }

        func preferenceSnapshot() -> [String: Any] {
            let defaults = UserDefaults.standard
            let domain = Bundle.main.bundleIdentifier ?? ""
            let synchronized = CFPreferencesAppSynchronize(domain as CFString)
            let cfPersistent = CFPreferencesCopyValue(languageKey as CFString, domain as CFString,
                                                       kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
            return ["persistent": typed(defaults.persistentDomain(forName: domain)?[languageKey]),
                    "cfPersistent": typed(cfPersistent), "cfSynchronizeSucceeded": synchronized,
                    "registered": typed(defaults.volatileDomain(forName: UserDefaults.registrationDomain)[languageKey]),
                    "argument": typed(defaults.volatileDomain(forName: UserDefaults.argumentDomain)[languageKey]),
                    "effective": typed(defaults.object(forKey: languageKey))]
        }

        func persistentLanguage() -> String? {
            guard let domain = Bundle.main.bundleIdentifier else { return nil }
            return UserDefaults.standard.persistentDomain(forName: domain)?[languageKey] as? String
        }

        func typed(_ raw: Any?) -> [String: Any] {
            guard let raw else { return ["type": "missing"] }
            if let value = raw as? String { return ["type": "string", "value": value] }
            return ["type": "unsupported", "description": String(describing: Swift.type(of: raw))]
        }

        func language(in snapshot: [String: Any], domain: String) -> String? {
            ((snapshot["preferences"] as? [String: Any])?[domain] as? [String: Any])?["value"] as? String
        }

        func type(in snapshot: [String: Any], domain: String) -> String? {
            ((snapshot["preferences"] as? [String: Any])?[domain] as? [String: Any])?["type"] as? String
        }

        func findPicker(displaying label: String) async throws -> AXUIElement {
            guard let window else { throw LanguageSelectionProbeFailure("The actual window is missing." ) }
            return try await unique("Expected one actual full-view language picker displaying English.", root: window) { node in
                let role = self.string(kAXRoleAttribute, node)
                return [kAXPopUpButtonRole, kAXComboBoxRole].contains(role ?? "") && self.controlDisplays(node, label: label)
            }
        }

        func controlDisplays(_ node: AXUIElement, label: String) -> Bool {
            [kAXValueAttribute, kAXTitleAttribute, kAXDescriptionAttribute].contains { string($0, node) == label }
        }

        func isWindowStillCurrent() -> Bool {
            guard let window else { return false }
            guard let focused = element(kAXFocusedWindowAttribute, app) else { return false }
            return CFEqual(window, focused) && string(kAXTitleAttribute, window) == "RJT language selection probe"
                && NSApp.isActive && NSApp.keyWindow?.title == "RJT language selection probe"
        }

        func checkedEvidence(_ item: AXUIElement) -> [String: Any] {
            ["markChar": typed(attribute("AXMenuItemMarkChar", item)),
             "selected": scalar(attribute(kAXSelectedAttribute, item)),
             "value": scalar(attribute(kAXValueAttribute, item)), "checked": isChecked(item)]
        }

        func isChecked(_ item: AXUIElement) -> Bool {
            if let mark = string("AXMenuItemMarkChar", item), !mark.isEmpty { return true }
            if let selected = attribute(kAXSelectedAttribute, item) as? NSNumber,
               CFGetTypeID(selected) == CFBooleanGetTypeID(), selected.boolValue { return true }
            if let value = attribute(kAXValueAttribute, item) as? NSNumber, value.doubleValue == 1 { return true }
            return false
        }

        func scalar(_ raw: Any?) -> [String: Any] {
            guard let raw else { return ["type": "missing"] }
            if let number = raw as? NSNumber {
                if CFGetTypeID(number) == CFBooleanGetTypeID() { return ["type": "boolean", "value": number.boolValue] }
                return ["type": "number", "value": number.doubleValue]
            }
            return typed(raw)
        }

        func unique(_ message: String, root: AXUIElement? = nil, matching: (AXUIElement) -> Bool) async throws -> AXUIElement {
            var found: AXUIElement?
            try await wait(message) {
                let matches = try self.nodes(root: root).filter { self.hasVisibleFrame($0) && matching($0) }
                if matches.count == 1 { found = matches[0]; return true }
                return false
            }
            guard let found else { throw LanguageSelectionProbeFailure(message) }
            return found
        }

        func nodes(root: AXUIElement? = nil) throws -> [AXUIElement] {
            var pending = [root ?? app]
            if case nil = root {
                for name in [kAXFocusedUIElementAttribute, kAXFocusedWindowAttribute, kAXMenuBarAttribute] {
                    if let node = element(name, app) { pending.append(node) }
                }
            }
            var seen: [AXUIElement] = []
            let end = min(deadline, ProcessInfo.processInfo.systemUptime + 1)
            while seen.count < 1200, ProcessInfo.processInfo.systemUptime < end, let node = pending.popLast() {
                if seen.contains(where: { CFEqual($0, node) }) { continue }
                _ = AXUIElementSetMessagingTimeout(node, 0.05)
                seen.append(node)
                pending.append(contentsOf: children(node))
            }
            try require(pending.isEmpty, "The accessibility census reached its time or node bound before completing.")
            return seen
        }

        func describe(_ node: AXUIElement) throws -> [String: Any] {
            var actions: CFArray?
            let error = AXUIElementCopyActionNames(node, &actions)
            var frame: [String: Double] = [:]
            if let value = attribute(kAXPositionAttribute, node), CFGetTypeID(value) == AXValueGetTypeID() {
                var point = CGPoint.zero
                if AXValueGetValue(value as! AXValue, .cgPoint, &point) { frame["x"] = point.x; frame["y"] = point.y }
            }
            if let value = attribute(kAXSizeAttribute, node), CFGetTypeID(value) == AXValueGetTypeID() {
                var size = CGSize.zero
                if AXValueGetValue(value as! AXValue, .cgSize, &size) { frame["width"] = size.width; frame["height"] = size.height }
            }
            let linkedTitle = element(kAXTitleUIElementAttribute, node)
            return ["role": string(kAXRoleAttribute, node) ?? "", "id": string(kAXIdentifierAttribute, node) ?? "",
                    "title": string(kAXTitleAttribute, node) ?? "", "description": string(kAXDescriptionAttribute, node) ?? "",
                    "value": scalar(attribute(kAXValueAttribute, node)), "titleUIElement": linkedTitle.map { string(kAXValueAttribute, $0) ?? string(kAXTitleAttribute, $0) ?? "" } ?? "",
                    "enabled": enabled(node), "actions": actions as? [String] ?? [], "actionsAXError": error.rawValue,
                    "frame": frame, "checked": checkedEvidence(node)]
        }

        func press(_ node: AXUIElement) throws {
            let details = try describe(node)
            try require(hasVisibleFrame(node) && enabled(node) && (details["actionsAXError"] as? NSNumber)?.intValue == Int(AXError.success.rawValue)
                        && (details["actions"] as? [String])?.contains(kAXPressAction) == true,
                        "The actual control is not visible, enabled and AXPress-capable.")
            try require(AXUIElementPerformAction(node, kAXPressAction as CFString) == .success, "The actual AXPress failed.")
        }

        func dumpHierarchy(_ name: String) throws {
            try writeJSON(try nodes().map { try describe($0) }, to: owner.output.appendingPathComponent(name + "-hierarchy.json"))
        }

        func screenshot(_ name: String) async throws {
            let path = owner.output.appendingPathComponent(name + ".png")
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            process.arguments = ["-x", "-t", "png", path.path]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            do { try await wait("Native screenshot timed out.", seconds: 5) { !process.isRunning } }
            catch { process.terminate(); throw error }
            try require(process.terminationStatus == 0 && FileManager.default.fileExists(atPath: path.path), "Native screenshot failed.")
        }

        func finish(classification: String, exitCode: Int, failure: String?) throws {
            let result: [String: Any] = [
                "schemaVersion": 1, "classification": classification, "completed": exitCode != 2, "exitCode": exitCode,
                "host": ["pid": Int(ProcessInfo.processInfo.processIdentifier), "bundleIdentifier": Bundle.main.bundleIdentifier ?? "", "executablePath": Bundle.main.executablePath ?? ""],
                "environment": environment, "model": model, "selectedCases": selectedCases,
                "executedCases": cases.filter { $0["completed"] as? Bool == true }.compactMap { $0["id"] },
                "baseline": baseline, "cases": cases, "primaryPersisted": primaryPersisted as Any? ?? NSNull(),
                "positiveControlsPassed": positiveControlsPassed, "issues": [], "failure": failure as Any? ?? NSNull(),
                "finalModelState": ["modelLoaded": owner.whisperModelManager.isModelLoaded,
                                    "contextAbsent": owner.whisperModelManager.whisperContext == nil],
                "runtimeBounds": ["unchangedFullView": true, "normalAppComposition": false, "modelLoaded": false,
                                  "ASR": false, "provider": false, "physicalInput": false],
                "runtimeBoundsEvidence": "Declared source composition; model/context observations are recorded separately. No inference, provider, engine or synthetic picker is invoked.",
                "setterEvidence": "No private setter instrumentation; inference is limited to the observed persistent-domain transition through the unchanged picker binding."
            ]
            try writeJSON(result, to: owner.output.appendingPathComponent("result.json"))
        }

        func writeJSON(_ value: Any, to path: URL) throws {
            try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]).write(to: path, options: .withoutOverwriting)
        }

        func wait(_ message: String, seconds: TimeInterval = 6, _ predicate: () throws -> Bool) async throws {
            let end = min(deadline, ProcessInfo.processInfo.systemUptime + seconds)
            repeat {
                if try predicate() { return }
                try await Task.sleep(for: .milliseconds(30))
            } while ProcessInfo.processInfo.systemUptime < end
            throw LanguageSelectionProbeFailure(message)
        }

        func require(_ condition: Bool, _ message: String) throws {
            if !condition { throw LanguageSelectionProbeFailure(message) }
        }
        func enabled(_ node: AXUIElement) -> Bool { (attribute(kAXEnabledAttribute, node) as? NSNumber)?.boolValue == true }
        func hasVisibleFrame(_ node: AXUIElement) -> Bool {
            guard (attribute("AXHidden", node) as? NSNumber)?.boolValue != true,
                  let value = attribute(kAXSizeAttribute, node), CFGetTypeID(value) == AXValueGetTypeID() else { return false }
            var size = CGSize.zero
            return AXValueGetValue(value as! AXValue, .cgSize, &size) && size.width > 0 && size.height > 0
        }
        func children(_ node: AXUIElement) -> [AXUIElement] { attribute(kAXChildrenAttribute, node) as? [AXUIElement] ?? [] }
        func string(_ name: String, _ node: AXUIElement) -> String? { attribute(name, node) as? String }
        func element(_ name: String, _ node: AXUIElement) -> AXUIElement? {
            guard let raw = attribute(name, node), CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
            return (raw as! AXUIElement)
        }
        func attribute(_ name: String, _ node: AXUIElement) -> CFTypeRef? {
            var value: CFTypeRef?
            return AXUIElementCopyAttributeValue(node, name as CFString, &value) == .success ? value : nil
        }
    }
}
