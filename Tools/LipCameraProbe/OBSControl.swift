import AppKit
import CryptoKit
import Darwin
import Foundation

@main
struct OBSControl {
    @MainActor
    static func main() async {
        let args = CommandLine.arguments
        guard args.count == 4 || (args.count == 5 && ["require-output", "stop-and-quit"].contains(args[4])) else { exit(2) }
        let requireOutput = args.count == 5 && args[4] == "require-output"
        let stopAndQuit = args.count == 5 && args[4] == "stop-and-quit"
        let configurationURL = URL(fileURLWithPath: args[1])
        let fixture = args[2]
        let reportURL = URL(fileURLWithPath: args[3])
        var results: [[String: Any]] = []
        var virtualCameraActive = false
        var frontendReady = false
        var phase = "connecting"
        var cleanup: [String: Any] = ["outputInactiveObserved": false, "processExitObserved": false]
        var cleanupIdentityVerified = false
        var cleanupClosed = false
        var ownedProcesses: [NSRunningApplication] = []
        func isOwned(_ app: NSRunningApplication) -> Bool {
            app.bundleIdentifier == "com.obsproject.obs-studio" &&
            app.bundleURL?.resolvingSymlinksInPath().path == "/Applications/OBS.app" &&
            app.executableURL?.resolvingSymlinksInPath().path == "/Applications/OBS.app/Contents/MacOS/OBS"
        }
        func processExists(_ pid: pid_t) -> Bool { kill(pid, 0) == 0 || errno != ESRCH }
        func writeReport() {
            var report: [String: Any] = ["requests": results, "virtualCameraActive": virtualCameraActive, "phase": phase]
            if requireOutput { report["frontendReady"] = frontendReady }
            if stopAndQuit { report["cleanup"] = cleanup; report["closed"] = cleanupClosed }
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: reportURL, options: .atomic)
            }
        }
        writeReport()
        do {
            if stopAndQuit {
                phase = "verifyingOwnedProducer"
                let environment = ProcessInfo.processInfo.environment
                let hostedMac = environment["GITHUB_ACTIONS"] == "true" && environment["RUNNER_OS"] == "macOS" && environment["RUNNER_ENVIRONMENT"] == "github-hosted"
                cleanup["githubHostedMac"] = hostedMac
                let expectedConfiguration = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/obs-studio/plugin_config/obs-websocket/config.json")
                guard hostedMac, configurationURL.resolvingSymlinksInPath() == expectedConfiguration.resolvingSymlinksInPath() else { throw ControlError.cleanupHostOrConfigurationMismatch }
                ownedProcesses = NSRunningApplication.runningApplications(withBundleIdentifier: "com.obsproject.obs-studio")
                guard ownedProcesses.allSatisfy({ $0.processIdentifier > 1 && isOwned($0) }) else { throw ControlError.cleanupProcessIdentityMismatch }
                cleanupIdentityVerified = true
                cleanup["ownedProcessIdentityVerified"] = true
                cleanup["processIDsBefore"] = ownedProcesses.map(\.processIdentifier)
                if ownedProcesses.isEmpty {
                    cleanup["producerAlreadyAbsent"] = true
                    cleanup["processExitObserved"] = true
                    throw ControlError.producerAbsentBeforeOutputObservation
                }
            }
            let config = try JSONSerialization.jsonObject(with: Data(contentsOf: configurationURL)) as! [String: Any]
            let password = config["server_password"] as! String
            let session = URLSession(configuration: .ephemeral)
            let socket = session.webSocketTask(with: URL(string: "ws://127.0.0.1:4455")!)
            socket.resume()
            defer { socket.cancel(with: .normalClosure, reason: nil); session.invalidateAndCancel() }
            func receive() async throws -> [String: Any] {
                let message = try await withThrowingTaskGroup(of: URLSessionWebSocketTask.Message.self) { group in
                    group.addTask { try await socket.receive() }
                    group.addTask {
                        try await Task.sleep(for: .seconds(stopAndQuit ? 3 : 10))
                        socket.cancel(with: .goingAway, reason: nil)
                        throw ControlError.responseDeadline
                    }
                    defer { group.cancelAll() }
                    guard let value = try await group.next() else { throw ControlError.protocolFailure }
                    return value
                }
                let data: Data
                switch message {
                case .string(let value): data = Data(value.utf8)
                case .data(let value): data = value
                @unknown default: throw ControlError.protocolFailure
                }
                return try JSONSerialization.jsonObject(with: data) as! [String: Any]
            }
            func send(_ value: [String: Any]) async throws {
                let data = try JSONSerialization.data(withJSONObject: value)
                try await socket.send(.string(String(decoding: data, as: UTF8.self)))
            }
            let hello = try await receive()
            let helloData = hello["d"] as? [String: Any] ?? [:]
            var identify: [String: Any] = ["rpcVersion": 1, "eventSubscriptions": 0]
            if let authentication = helloData["authentication"] as? [String: String],
               let salt = authentication["salt"], let challenge = authentication["challenge"] {
                let secret = Data(SHA256.hash(data: Data((password + salt).utf8))).base64EncodedString()
                identify["authentication"] = Data(SHA256.hash(data: Data((secret + challenge).utf8))).base64EncodedString()
            }
            try await send(["op": 1, "d": identify])
            let identified = try await receive()
            guard identified["op"] as? Int == 2 else { throw ControlError.protocolFailure }
            phase = "authenticated"
            writeReport()
            @discardableResult
            func request(_ name: String, _ data: [String: Any] = [:]) async throws -> [String: Any] {
                let id = UUID().uuidString
                try await send(["op": 6, "d": ["requestType": name, "requestId": id, "requestData": data]])
                for _ in 0..<20 {
                    let response = try await receive()
                    guard response["op"] as? Int == 7,
                          let details = response["d"] as? [String: Any], details["requestId"] as? String == id else { continue }
                    results.append(["request": name, "status": details["requestStatus"] ?? [:], "data": details["responseData"] ?? [:]])
                    writeReport()
                    return details
                }
                throw ControlError.protocolFailure
            }
            if stopAndQuit {
                phase = "stoppingVirtualCamera"
                let state = try await request("GetVirtualCamStatus")
                guard (state["requestStatus"] as? [String: Any])?["result"] as? Bool == true,
                      let active = (state["responseData"] as? [String: Any])?["outputActive"] as? Bool else { throw ControlError.virtualCameraStatusUnavailable }
                virtualCameraActive = active
                if active {
                    let stopped = try await request("StopVirtualCam")
                    guard (stopped["requestStatus"] as? [String: Any])?["result"] as? Bool == true else { throw ControlError.virtualCameraStopRejected }
                }
                let deadline = ContinuousClock.now.advanced(by: .seconds(10))
                repeat {
                    let observed = try await request("GetVirtualCamStatus")
                    if (observed["requestStatus"] as? [String: Any])?["result"] as? Bool == true,
                       let active = (observed["responseData"] as? [String: Any])?["outputActive"] as? Bool {
                        virtualCameraActive = active
                        if !active { cleanup["outputInactiveObserved"] = true; break }
                    }
                    try await Task.sleep(for: .milliseconds(200))
                } while ContinuousClock.now < deadline
                guard cleanup["outputInactiveObserved"] as? Bool == true else { throw ControlError.virtualCameraStopUnobserved }
            } else {
                if requireOutput {
                    phase = "waitingForFrontend"
                    for check in 0..<20 {
                        if check > 0 { try await Task.sleep(for: .seconds(1)) }
                        let state = try await request("GetSceneList")
                        frontendReady = (state["requestStatus"] as? [String: Any])?["result"] as? Bool == true
                        if frontendReady { break }
                    }
                    guard frontendReady else { throw ControlError.frontendNotReady }
                }
                phase = "configuringSource"
                try await request("SetVideoSettings", ["baseWidth": 640, "baseHeight": 480, "outputWidth": 640, "outputHeight": 480, "fpsNumerator": 25, "fpsDenominator": 1])
                try await request("CreateScene", ["sceneName": "RJTLipProof"])
                try await request("CreateInput", ["sceneName": "RJTLipProof", "inputName": "PublicSilentVideo", "inputKind": "ffmpeg_source", "inputSettings": ["is_local_file": true, "local_file": fixture, "looping": true, "restart_on_activate": true, "clear_on_media_end": false], "sceneItemEnabled": true])
                try await request("SetInputMute", ["inputName": "PublicSilentVideo", "inputMuted": true])
                try await request("SetCurrentProgramScene", ["sceneName": "RJTLipProof"])
                try await request("TriggerMediaInputAction", ["inputName": "PublicSilentVideo", "mediaAction": "OBS_WEBSOCKET_MEDIA_INPUT_ACTION_RESTART"])
                if requireOutput {
                    try await request("GetCurrentProgramScene")
                    try await request("GetSceneItemList", ["sceneName": "RJTLipProof"])
                    try await request("GetInputSettings", ["inputName": "PublicSilentVideo"])
                    try await request("GetMediaInputStatus", ["inputName": "PublicSilentVideo"])
                }
                phase = "startingVirtualCamera"
                try await request("StartVirtualCam")
                for check in 0..<(requireOutput ? 15 : 1) {
                    if check > 0 { try await Task.sleep(for: .seconds(1)) }
                    let state = try await request("GetVirtualCamStatus")
                    virtualCameraActive = (state["responseData"] as? [String: Any])?["outputActive"] as? Bool == true
                    if virtualCameraActive { break }
                }
                phase = virtualCameraActive ? "active" : "inactive"
            }
        } catch {
            results.append(["error": String(describing: error)])
        }
        if stopAndQuit && cleanupIdentityVerified {
            phase = "quittingOwnedProducer"
            // Stop failures still get a normal quit attempt, but cannot produce a successful receipt.
            var requests: [[String: Any]] = []
            for app in ownedProcesses {
                let pid = app.processIdentifier
                guard processExists(pid) else { continue }
                guard let current = NSRunningApplication(processIdentifier: pid), isOwned(current) else {
                    requests.append(["pid": pid, "identityMatched": false])
                    continue
                }
                requests.append(["pid": pid, "identityMatched": true, "terminateAccepted": current.terminate()])
            }
            cleanup["quitRequests"] = requests
            writeReport()
            let deadline = ContinuousClock.now.advanced(by: .seconds(15))
            repeat {
                let remaining = ownedProcesses.map(\.processIdentifier).filter(processExists)
                cleanup["remainingProcessIDs"] = remaining
                if remaining.isEmpty { cleanup["processExitObserved"] = true; break }
                try? await Task.sleep(for: .milliseconds(200))
            } while ContinuousClock.now < deadline
            cleanupClosed = cleanup["outputInactiveObserved"] as? Bool == true && cleanup["processExitObserved"] as? Bool == true
            phase = cleanupClosed ? "closed" : "cleanupFailed"
        }
        writeReport()
        if stopAndQuit { exit(cleanupClosed ? 0 : 1) }
        if requireOutput && !virtualCameraActive { exit(1) }
    }
    enum ControlError: Error {
        case protocolFailure, frontendNotReady, responseDeadline, cleanupHostOrConfigurationMismatch
        case cleanupProcessIdentityMismatch, producerAbsentBeforeOutputObservation
        case virtualCameraStatusUnavailable, virtualCameraStopRejected, virtualCameraStopUnobserved
    }
}
