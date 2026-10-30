import CryptoKit
import Darwin
import Foundation

@main
struct OBSControl {
    static func main() async {
        let args = CommandLine.arguments
        guard args.count == 4 || (args.count == 5 && args[4] == "require-output") else { return }
        let requireOutput = args.count == 5
        let configurationURL = URL(fileURLWithPath: args[1])
        let fixture = args[2]
        let reportURL = URL(fileURLWithPath: args[3])
        var results: [[String: Any]] = []
        var virtualCameraActive = false
        do {
            let config = try JSONSerialization.jsonObject(with: Data(contentsOf: configurationURL)) as! [String: Any]
            let password = config["server_password"] as! String
            let session = URLSession(configuration: .ephemeral)
            let socket = session.webSocketTask(with: URL(string: "ws://127.0.0.1:4455")!)
            socket.resume()
            defer { socket.cancel(with: .normalClosure, reason: nil); session.invalidateAndCancel() }
            func receive() async throws -> [String: Any] {
                let message = try await socket.receive()
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
            @discardableResult
            func request(_ name: String, _ data: [String: Any] = [:]) async throws -> [String: Any] {
                let id = UUID().uuidString
                try await send(["op": 6, "d": ["requestType": name, "requestId": id, "requestData": data]])
                for _ in 0..<20 {
                    let response = try await receive()
                    guard response["op"] as? Int == 7,
                          let details = response["d"] as? [String: Any], details["requestId"] as? String == id else { continue }
                    results.append(["request": name, "status": details["requestStatus"] ?? [:], "data": details["responseData"] ?? [:]])
                    return details
                }
                throw ControlError.protocolFailure
            }
            try await request("SetVideoSettings", ["baseWidth": 640, "baseHeight": 480, "outputWidth": 640, "outputHeight": 480, "fpsNumerator": 25, "fpsDenominator": 1])
            try await request("CreateScene", ["sceneName": "RJTLipProof"])
            try await request("CreateInput", ["sceneName": "RJTLipProof", "inputName": "PublicSilentVideo", "inputKind": "ffmpeg_source", "inputSettings": ["is_local_file": true, "local_file": fixture, "looping": true, "restart_on_activate": true, "clear_on_media_end": false], "sceneItemEnabled": true])
            try await request("SetInputMute", ["inputName": "PublicSilentVideo", "inputMuted": true])
            try await request("SetCurrentProgramScene", ["sceneName": "RJTLipProof"])
            try await request("TriggerMediaInputAction", ["inputName": "PublicSilentVideo", "mediaAction": "OBS_WEBSOCKET_MEDIA_INPUT_ACTION_RESTART"])
            try await request("StartVirtualCam")
            for check in 0..<(requireOutput ? 15 : 1) {
                if check > 0 { try await Task.sleep(for: .seconds(1)) }
                let state = try await request("GetVirtualCamStatus")
                virtualCameraActive = (state["responseData"] as? [String: Any])?["outputActive"] as? Bool == true
                if virtualCameraActive { break }
            }
        } catch {
            results.append(["error": String(describing: error)])
        }
        if let data = try? JSONSerialization.data(withJSONObject: ["requests": results, "virtualCameraActive": virtualCameraActive], options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: reportURL, options: .atomic)
        }
        if requireOutput && !virtualCameraActive { exit(1) }
    }
    enum ControlError: Error { case protocolFailure }
}
