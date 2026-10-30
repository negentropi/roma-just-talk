import CryptoKit
import Foundation

public enum LipModelStoreError: LocalizedError, Sendable, Equatable {
    case missingResources, invalidManifest, notInstalled, verificationFailed
    case downloadFailed, extractionFailed, installationFailed
    case insufficientSpace(requiredGigabytes: Int64)

    public var errorDescription: String? {
        switch self {
        case .missingResources: return "The lip model resources are missing."
        case .invalidManifest: return "The lip model manifest is invalid."
        case .notInstalled: return "Install the lip model before using lip dictation."
        case .verificationFailed: return "The lip model files failed verification. Reinstall the model."
        case .downloadFailed: return "The lip model download failed. Please try again."
        case .extractionFailed: return "The lip model could not be extracted."
        case .installationFailed: return "The lip model could not be installed. Check available storage and try again."
        case .insufficientSpace(let gigabytes): return "The lip model needs at least \(gigabytes) GB of free storage to install."
        }
    }
}

/// Downloads the publisher's checkpoint only after an explicit installation request.
public actor LipModelStore {
    private struct Operation {
        let id = UUID()
        let installing: Bool
        let task: Task<URL, Error>
    }

    private let directory: URL
    private let resources: URL
    private let download: @Sendable (URL, URL) async throws -> Void
    private var operation: Operation?
    private var verifiedURL: URL?
    private var manifestResult: Result<Manifest, LipModelStoreError>?

    public init(directory: URL) {
        self.directory = directory.standardizedFileURL.resolvingSymlinksInPath()
        self.resources = Bundle.module.url(forResource: "Resources", withExtension: nil)
            ?? Bundle.module.bundleURL.appendingPathComponent("Resources", isDirectory: true)
        self.download = { try await Self.downloadCheckpoint(from: $0, to: $1) }
    }

    // Tiny checkpoint fixtures exercise the real extraction and publication boundary.
    init(directory: URL, resources: URL, download: @escaping @Sendable (URL, URL) async throws -> Void) {
        self.directory = directory.standardizedFileURL.resolvingSymlinksInPath()
        self.resources = resources
        self.download = download
    }

    /// Settings checks read a small completion receipt and file metadata, never model hashes.
    public func isInstalled() -> Bool {
        guard let manifest = try? loadManifest() else { return false }
        return Self.hasReceipt(in: installationDirectory(for: manifest), manifest: manifest)
    }

    public func installationBytes() throws -> (download: Int64, installed: Int64, temporaryFreeSpace: Int64) {
        let manifest = try loadManifest()
        return (manifest.checkpointBytes, manifest.storageBytes + manifest.graphBytes,
                manifest.checkpointBytes + manifest.storageBytes + 100_000_000)
    }

    public func install() async throws -> URL {
        if let operation {
            do { return try await finish(operation) }
            catch {
                if operation.installing || error is CancellationError { throw error }
            }
        }
        if let verifiedURL, isInstalled() { return verifiedURL }
        // Recheck after an awaited verification so concurrent callers share one installer.
        if let operation { return try await finish(operation) }
        let manifest = try loadManifest()
        let directory = directory, resources = resources, download = download
        let operation = Operation(installing: true, task: Task.detached(priority: .utility) {
            try await Self.install(in: directory, resources: resources, manifest: manifest, download: download)
        })
        self.operation = operation
        return try await finish(operation)
    }

    /// Verifies every graph/storage byte before the first inference in this process.
    public func modelURL() async throws -> URL {
        if let operation { return try await finish(operation) }
        if let verifiedURL, isInstalled() { return verifiedURL }
        let directory = directory, manifest = try loadManifest()
        let operation = Operation(installing: false, task: Task.detached(priority: .utility) {
            let installed = Self.installationDirectory(in: directory, manifest: manifest)
            guard Self.hasReceipt(in: installed, manifest: manifest) else {
                throw LipModelStoreError.notInstalled
            }
            do {
                try Self.verifyInstallation(at: installed, manifest: manifest)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                try Task.checkCancellation()
                // Failed integrity must survive settings refresh without deleting model data.
                try FileManager.default.removeItem(at: installed.appendingPathComponent("complete"))
                throw error
            }
            return installed.appendingPathComponent("visual-ctc.onnx")
        })
        self.operation = operation
        return try await finish(operation)
    }

    public func cancelInstallation() async {
        guard let operation, operation.installing else { return }
        operation.task.cancel()
        _ = await operation.task.result
        if self.operation?.id == operation.id { self.operation = nil }
    }

    private func finish(_ operation: Operation) async throws -> URL {
        do {
            let url = try await withTaskCancellationHandler {
                try await operation.task.value
            } onCancel: {
                operation.task.cancel()
            }
            if self.operation?.id == operation.id { self.operation = nil }
            verifiedURL = url
            return url
        } catch {
            if self.operation?.id == operation.id {
                self.operation = nil
                verifiedURL = nil
            }
            if error is CancellationError || operation.task.isCancelled { throw CancellationError() }
            throw (error as? LipModelStoreError) ?? .installationFailed
        }
    }

    private func loadManifest() throws -> Manifest {
        if let manifestResult { return try manifestResult.get() }
        let result = Result { try Manifest.load(from: resources) }
            .mapError { ($0 as? LipModelStoreError) ?? .invalidManifest }
        manifestResult = result
        return try result.get()
    }

    private func installationDirectory(for manifest: Manifest) -> URL {
        Self.installationDirectory(in: directory, manifest: manifest)
    }

    private static func installationDirectory(in directory: URL, manifest: Manifest) -> URL {
        directory.appendingPathComponent("raven-\(manifest.identity)", isDirectory: true)
    }

    private static func install(
        in directory: URL, resources: URL, manifest: Manifest,
        download: @Sendable (URL, URL) async throws -> Void
    ) async throws -> URL {
        let installed = installationDirectory(in: directory, manifest: manifest)
        if hasReceipt(in: installed, manifest: manifest) {
            do {
                try verifyInstallation(at: installed, manifest: manifest)
                return installed.appendingPathComponent("visual-ctc.onnx")
            } catch is CancellationError { throw CancellationError() }
            catch { /* An explicit installation also repairs an incomplete/corrupt model. */ }
        }
        try Task.checkCancellation()
        let files = FileManager.default
        try files.createDirectory(at: directory, withIntermediateDirectories: true)
        try requireDirectory(directory)
        let requiredBytes = manifest.checkpointBytes + manifest.storageBytes + 100_000_000
        if let available = try? directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage,
           available < requiredBytes {
            throw LipModelStoreError.insufficientSpace(requiredGigabytes: requiredBytes / 1_000_000_000 + (requiredBytes % 1_000_000_000 == 0 ? 0 : 1))
        }
        let staging = directory.appendingPathComponent(".install-\(UUID().uuidString)", isDirectory: true)
        try files.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? files.removeItem(at: staging) }
        let checkpoint = staging.appendingPathComponent("checkpoint.zip")
        try await download(manifest.checkpointURL, checkpoint)
        try verifyFile(checkpoint, bytes: manifest.checkpointBytes, sha256: manifest.checkpointSHA256)
        let extracted = staging.appendingPathComponent("extracted", isDirectory: true)
        let candidate = staging.appendingPathComponent("model", isDirectory: true)
        try files.createDirectory(at: extracted, withIntermediateDirectories: false)
        try files.createDirectory(at: candidate.appendingPathComponent("storages"), withIntermediateDirectories: true)
        // Flattening forbids archive directories/symlink parents from choosing destinations.
        let entries = manifest.storages.values.map(\.zipEntry).sorted()
        try await Extraction.run(arguments: ["-j", "-qq", checkpoint.path] + entries + ["-d", extracted.path])
        for (path, storage) in manifest.storages {
            let source = extracted.appendingPathComponent((storage.zipEntry as NSString).lastPathComponent)
            try verifyFile(source, bytes: storage.bytes, sha256: storage.sha256)
            try files.moveItem(at: source, to: candidate.appendingPathComponent(path))
        }
        let graph = resources.appendingPathComponent("visual-ctc.onnx")
        try verifyFile(graph, bytes: manifest.graphBytes, sha256: manifest.graphSHA256)
        try files.copyItem(at: graph, to: candidate.appendingPathComponent("visual-ctc.onnx"))
        try Data(manifest.identity.utf8).write(to: candidate.appendingPathComponent("complete"), options: .atomic)
        try Task.checkCancellation()
        // A same-volume rename publishes only the fully verified directory.
        if files.fileExists(atPath: installed.path) {
            // This content-addressed directory belongs solely to this store.
            try requireDirectory(installed)
            try files.removeItem(at: installed)
        }
        try files.moveItem(at: candidate, to: installed)
        return installed.appendingPathComponent("visual-ctc.onnx")
    }

    private static func hasReceipt(in directory: URL, manifest: Manifest) -> Bool {
        do {
            try requireDirectory(directory)
            try requireDirectory(directory.appendingPathComponent("storages"))
            guard try regularFileSize(directory.appendingPathComponent("complete")) == Int64(manifest.identity.utf8.count),
                  try Data(contentsOf: directory.appendingPathComponent("complete")) == Data(manifest.identity.utf8),
                  try regularFileSize(directory.appendingPathComponent("visual-ctc.onnx")) == manifest.graphBytes else {
                return false
            }
            for (path, storage) in manifest.storages {
                guard try regularFileSize(directory.appendingPathComponent(path)) == storage.bytes else { return false }
            }
            return true
        } catch { return false }
    }

    private static func verifyInstallation(at directory: URL, manifest: Manifest) throws {
        try requireDirectory(directory)
        try requireDirectory(directory.appendingPathComponent("storages"))
        try verifyFile(directory.appendingPathComponent("visual-ctc.onnx"), bytes: manifest.graphBytes, sha256: manifest.graphSHA256)
        for (path, storage) in manifest.storages {
            try verifyFile(directory.appendingPathComponent(path), bytes: storage.bytes, sha256: storage.sha256)
        }
    }

    private static func requireDirectory(_ url: URL) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeDirectory else {
            throw LipModelStoreError.verificationFailed
        }
    }

    private static func regularFileSize(_ url: URL) throws -> Int64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              let size = attributes[.size] as? NSNumber else {
            throw LipModelStoreError.verificationFailed
        }
        return size.int64Value
    }

    private static func verifyFile(_ url: URL, bytes: Int64, sha256: String) throws {
        try Task.checkCancellation()
        guard try regularFileSize(url) == bytes else { throw LipModelStoreError.verificationFailed }
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var hash = SHA256()
        while let data = try file.read(upToCount: 1_048_576), !data.isEmpty {
            try Task.checkCancellation()
            hash.update(data: data)
        }
        guard hex(hash.finalize()) == sha256 else { throw LipModelStoreError.verificationFailed }
    }

    private static func hex<D: Sequence>(_ digest: D) -> String where D.Element == UInt8 {
        digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func downloadCheckpoint(from url: URL, to destination: URL) async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration, delegate: PublicDownloadDelegate(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        try await withTaskCancellationHandler {
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
            request.httpShouldHandleCookies = false
            do {
                let (temporary, response) = try await session.download(for: request)
                guard let response = response as? HTTPURLResponse, response.statusCode == 200,
                      response.url?.scheme?.lowercased() == "https" else {
                    throw LipModelStoreError.downloadFailed
                }
                try Task.checkCancellation()
                try FileManager.default.moveItem(at: temporary, to: destination)
            } catch {
                if Task.isCancelled { throw CancellationError() }
                throw LipModelStoreError.downloadFailed
            }
        } onCancel: {
            session.invalidateAndCancel()
        }
    }

    private final class PublicDownloadDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
            answer(challenge, completionHandler: completionHandler)
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
                        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
            answer(challenge, completionHandler: completionHandler)
        }

        private func answer(_ challenge: URLAuthenticationChallenge,
                            completionHandler: (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
            completionHandler(challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust
                              ? .performDefaultHandling : .cancelAuthenticationChallenge, nil)
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            guard let url = request.url, url.scheme?.lowercased() == "https", url.user == nil, url.password == nil else {
                completionHandler(nil)
                return
            }
            var request = request
            request.httpShouldHandleCookies = false
            for header in ["Authorization", "Proxy-Authorization", "Cookie"] { request.setValue(nil, forHTTPHeaderField: header) }
            completionHandler(request)
        }
    }

    private struct Manifest: Decodable, Sendable {
        struct Storage: Decodable, Sendable {
            let zipEntry: String
            let bytes: Int64
            let sha256: String
            enum CodingKeys: String, CodingKey { case zipEntry = "zip_entry", bytes, sha256 }
        }
        let formatVersion: Int
        let checkpointURL: URL
        let checkpointSHA256: String
        let checkpointBytes: Int64
        let graphSHA256: String
        let graphBytes: Int64
        let sourceRevision: String
        let storages: [String: Storage]
        var identity = ""
        var storageBytes: Int64 { storages.values.reduce(0) { $0 + $1.bytes } }

        enum CodingKeys: String, CodingKey {
            case formatVersion = "format_version", checkpointURL = "checkpoint_url"
            case checkpointSHA256 = "checkpoint_sha256", checkpointBytes = "checkpoint_bytes"
            case graphSHA256 = "graph_sha256", graphBytes = "graph_bytes"
            case sourceRevision = "source_revision", storages
        }

        static func load(from resources: URL) throws -> Self {
            let data: Data
            do { data = try Data(contentsOf: resources.appendingPathComponent("manifest.json")) }
            catch { throw LipModelStoreError.missingResources }
            do {
                var manifest = try JSONDecoder().decode(Self.self, from: data)
                try manifest.validate()
                manifest.identity = LipModelStore.hex(SHA256.hash(data: data))
                return manifest
            } catch { throw LipModelStoreError.invalidManifest }
        }

        private func validate() throws {
            let url = URLComponents(url: checkpointURL, resolvingAgainstBaseURL: false)
            guard formatVersion == 1, url?.scheme?.lowercased() == "https",
                  !(url?.host?.isEmpty ?? true), url?.user == nil, url?.password == nil,
                  checkpointBytes > 0, graphBytes > 0,
                  Self.isHex(checkpointSHA256, count: 64), Self.isHex(graphSHA256, count: 64),
                  Self.isHex(sourceRevision, count: 40), !storages.isEmpty, storages.count <= 10_000 else {
                throw LipModelStoreError.invalidManifest
            }
            var destinations = Set<String>(), entries = Set<String>(), basenames = Set<String>()
            var totalStorageBytes: Int64 = 0
            for (destination, storage) in storages {
                let (newTotal, overflow) = totalStorageBytes.addingReportingOverflow(storage.bytes)
                guard !overflow, newTotal > 0 else { throw LipModelStoreError.invalidManifest }
                totalStorageBytes = newTotal
                let parts = destination.split(separator: "/", omittingEmptySubsequences: false)
                guard Self.isSafePath(destination), parts.count == 2, parts[0] == "storages",
                      parts[1].hasSuffix(".bin"), Self.isSafePath(storage.zipEntry),
                      storage.bytes > 0, storage.bytes <= checkpointBytes,
                      Self.isHex(storage.sha256, count: 64),
                      destinations.insert(destination.lowercased()).inserted,
                      entries.insert(storage.zipEntry.lowercased()).inserted,
                      basenames.insert((storage.zipEntry as NSString).lastPathComponent.lowercased()).inserted else {
                    throw LipModelStoreError.invalidManifest
                }
            }
            guard checkpointBytes <= Int64.max - totalStorageBytes - 100_000_000 else { throw LipModelStoreError.invalidManifest }
        }

        private static func isHex(_ string: String, count: Int) -> Bool {
            string.utf8.count == count && string.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
        }

        private static func isSafePath(_ path: String) -> Bool {
            let parts = path.split(separator: "/", omittingEmptySubsequences: false)
            return !parts.isEmpty && parts.allSatisfy { part in
                !part.isEmpty && part != "." && part != ".." && part.first != "-" && part.utf8.allSatisfy {
                    (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || [45, 46, 95].contains($0)
                }
            }
        }
    }

    private final class Extraction: @unchecked Sendable {
        private let lock = NSLock()
        private var process: Process?
        private var cancelled = false

        static func run(arguments: [String]) async throws {
            let extraction = Extraction()
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    extraction.start(arguments: arguments, continuation: continuation)
                }
                try Task.checkCancellation()
            } onCancel: {
                extraction.cancel()
            }
        }

        private func start(arguments: [String], continuation: CheckedContinuation<Void, Error>) {
            lock.lock()
            defer { lock.unlock() }
            guard !cancelled else { continuation.resume(throwing: CancellationError()); return }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            process.arguments = arguments
            process.environment = ["PATH": "/usr/bin:/bin", "LANG": "C", "LC_ALL": "C"]
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { process in
                if process.terminationStatus == 0 { continuation.resume() }
                else { continuation.resume(throwing: LipModelStoreError.extractionFailed) }
            }
            do {
                try process.run()
                self.process = process
            } catch { continuation.resume(throwing: LipModelStoreError.extractionFailed) }
        }

        private func cancel() {
            lock.lock()
            defer { lock.unlock() }
            cancelled = true
            if let process, process.isRunning { process.terminate() }
        }
    }
}
