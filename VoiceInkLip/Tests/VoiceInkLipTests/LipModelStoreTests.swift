import CryptoKit
import Foundation
import XCTest
@testable import VoiceInkLip

final class LipModelStoreTests: XCTestCase {
    func testMissingInstallationNeverDownloadsOrCreatesStorage() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let downloads = Counter()
        let store = fixture.store(downloads: downloads)
        let installed = await store.isInstalled()
        XCTAssertFalse(installed)
        do {
            _ = try await store.modelURL()
            XCTFail("Missing model must not be usable")
        } catch let error as LipModelStoreError {
            XCTAssertEqual(error, .notInstalled)
        }
        let downloadCount = await downloads.value
        XCTAssertEqual(downloadCount, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.directory.path))
    }

    func testTinyPublisherArchiveInstallsOnlyWhitelistedStorageAndIsIdempotent() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let downloads = Counter()
        let store = fixture.store(downloads: downloads)
        async let first = store.install()
        async let second = store.install()
        let (firstURL, secondURL) = try await (first, second)
        XCTAssertEqual(firstURL, secondURL)
        XCTAssertEqual(try Data(contentsOf: firstURL), Fixture.graph)
        XCTAssertEqual(try Data(contentsOf: firstURL.deletingLastPathComponent().appendingPathComponent("storages/0.bin")), Fixture.storage)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: firstURL.deletingLastPathComponent().path).sorted(), ["complete", "storages", "visual-ctc.onnx"])
        let initialDownloads = await downloads.value
        let installed = await store.isInstalled()
        let installedAgain = try await store.install()
        let restarted = fixture.store(downloads: downloads)
        let verifiedAfterRestart = try await restarted.modelURL()
        let finalDownloads = await downloads.value
        XCTAssertEqual(initialDownloads, 1)
        XCTAssertTrue(installed)
        XCTAssertEqual(installedAgain, firstURL)
        XCTAssertEqual(verifiedAfterRestart, firstURL)
        XCTAssertEqual(finalDownloads, 1)
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: fixture.directory.path).contains { $0.hasPrefix(".install-") })
    }

    func testUnsafeManifestPathsRejectedBeforeDownloading() async throws {
        for (destination, entry) in [
            ("../escape.bin", "archive/data/0"),
            ("storages/0.bin", "archive/../../escape"),
            ("storages/0.bin", "archive/data/*"),
            ("storages/0.bin", "-outside")
        ] {
            let fixture = try Fixture(destination: destination, entry: entry)
            defer { fixture.cleanUp() }
            let downloads = Counter()
            let store = fixture.store(downloads: downloads)
            do {
                _ = try await store.install()
                XCTFail("Unsafe manifest must fail")
            } catch let error as LipModelStoreError {
                XCTAssertEqual(error, .invalidManifest)
            }
            let downloadCount = await downloads.value
            XCTAssertEqual(downloadCount, 0)
            XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.directory.path))
        }
    }

    func testInvalidManifestFieldsAndAmbiguousArchiveNamesRejectedBeforeDownload() async throws {
        let invalidFields: [(String, Any)] = [
            ("checkpoint_url", "http://example.invalid/checkpoint"),
            ("checkpoint_url", "https://user:password@example.invalid/checkpoint"),
            ("checkpoint_sha256", "not a digest"),
            ("checkpoint_bytes", 0),
            ("source_revision", "unknown"),
            ("graph_bytes", -1)
        ]
        for (key, value) in invalidFields {
            let fixture = try Fixture()
            defer { fixture.cleanUp() }
            try fixture.updateManifest { $0[key] = value }
            let downloads = Counter()
            do { _ = try await fixture.store(downloads: downloads).install(); XCTFail("Invalid manifest must fail") }
            catch let error as LipModelStoreError { XCTAssertEqual(error, .invalidManifest) }
            let count = await downloads.value
            XCTAssertEqual(count, 0)
        }
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try fixture.updateManifest { manifest in
            var storages = manifest["storages"] as! [String: [String: Any]]
            var duplicate = storages["storages/0.bin"]!
            duplicate["zip_entry"] = "different/path/0"
            storages["storages/1.bin"] = duplicate
            manifest["storages"] = storages
        }
        let downloads = Counter()
        do { _ = try await fixture.store(downloads: downloads).install(); XCTFail("Flattened archive names must be unique") }
        catch let error as LipModelStoreError { XCTAssertEqual(error, .invalidManifest) }
        let count = await downloads.value
        XCTAssertEqual(count, 0)
    }

    func testKnownInsufficientStorageFailsBeforeDownload() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        guard let available = try fixture.root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage,
              available >= 0, available < Int64.max / 2 else {
            throw XCTSkip("This volume does not report available capacity")
        }
        let checkpointBytes = available + 1_000_000_000
        try fixture.updateManifest { $0["checkpoint_bytes"] = checkpointBytes }
        let downloads = Counter()
        do {
            _ = try await fixture.store(downloads: downloads).install()
            XCTFail("Known insufficient storage must stop before the download")
        } catch let error as LipModelStoreError {
            let required = checkpointBytes + Int64(Fixture.storage.count) + 100_000_000
            XCTAssertEqual(error, .insufficientSpace(requiredGigabytes: required / 1_000_000_000 + (required % 1_000_000_000 == 0 ? 0 : 1)))
        }
        let count = await downloads.value
        XCTAssertEqual(count, 0)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: fixture.directory.path), [])
    }

    func testCheckpointHashFailurePreventsExtractionAndCleansStaging() async throws {
        let fixture = try Fixture(checkpointHash: String(repeating: "0", count: 64))
        defer { fixture.cleanUp() }
        let store = fixture.store()
        do {
            _ = try await store.install()
            XCTFail("Unverified publisher archive must fail")
        } catch let error as LipModelStoreError {
            XCTAssertEqual(error, .verificationFailed)
        }
        let installed = await store.isInstalled()
        XCTAssertFalse(installed)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: fixture.directory.path), [])
    }

    func testStorageHashFailureNeverPublishesModel() async throws {
        let fixture = try Fixture(storageHash: String(repeating: "0", count: 64))
        defer { fixture.cleanUp() }
        let store = fixture.store()
        do {
            _ = try await store.install()
            XCTFail("Unverified storage must fail")
        } catch let error as LipModelStoreError {
            XCTAssertEqual(error, .verificationFailed)
        }
        let installed = await store.isInstalled()
        XCTAssertFalse(installed)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: fixture.directory.path), [])
    }

    func testRestartVerifiesSameSizeCorruptionBeforeInferenceAndExplicitInstallRepairs() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let model = try await fixture.store().install()
        let storage = model.deletingLastPathComponent().appendingPathComponent("storages/0.bin")
        let corruptedStorage = Data(repeating: 0, count: Fixture.storage.count)
        try corruptedStorage.write(to: storage)
        let unrelated = fixture.directory.appendingPathComponent("unrelated")
        try Data("keep".utf8).write(to: unrelated)
        let restarted = fixture.store()
        let installedBeforeVerification = await restarted.isInstalled()
        XCTAssertTrue(installedBeforeVerification, "Metadata cannot detect same-size corruption")
        do {
            _ = try await restarted.modelURL()
            XCTFail("A completion receipt must not bypass first-inference verification")
        } catch let error as LipModelStoreError {
            XCTAssertEqual(error, .verificationFailed)
        }
        let installedAfterVerification = await restarted.isInstalled()
        XCTAssertFalse(installedAfterVerification, "Failed integrity verification must expose installation retry")
        let installedAfterRestart = await fixture.store().isInstalled()
        XCTAssertFalse(installedAfterRestart, "Invalidation must survive another store instance")
        XCTAssertEqual(try Data(contentsOf: storage), corruptedStorage, "Integrity failure must preserve model files")
        XCTAssertEqual(try Data(contentsOf: unrelated), Data("keep".utf8))
        let repaired = try await restarted.install()
        XCTAssertEqual(repaired, model)
        XCTAssertEqual(try Data(contentsOf: storage), Fixture.storage)
        let usableModel = try await restarted.modelURL()
        XCTAssertEqual(usableModel, model)
        let installedAfterRepair = await fixture.store().isInstalled()
        XCTAssertTrue(installedAfterRepair)
        XCTAssertEqual(try Data(contentsOf: unrelated), Data("keep".utf8))
    }

    func testMissingStorageAndSymlinkedStorageAreNotInstalled() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let model = try await fixture.store().install()
        let storage = model.deletingLastPathComponent().appendingPathComponent("storages/0.bin")
        try FileManager.default.removeItem(at: storage)
        let missingInstalled = await fixture.store().isInstalled()
        XCTAssertFalse(missingInstalled)
        let outside = fixture.root.appendingPathComponent("outside")
        try Fixture.storage.write(to: outside)
        try FileManager.default.createSymbolicLink(at: storage, withDestinationURL: outside)
        let symlinkInstalled = await fixture.store().isInstalled()
        XCTAssertFalse(symlinkInstalled)
        do {
            _ = try await fixture.store().modelURL()
            XCTFail("Symlinks must not escape the model store")
        } catch let error as LipModelStoreError {
            XCTAssertEqual(error, .notInstalled)
        }
    }

    func testCancellationDrainsDownloadAndRemovesOnlyItsStaging() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let started = expectation(description: "download started")
        let drained = expectation(description: "download drained")
        let attempts = Counter()
        let checkpoint = fixture.checkpoint
        let store = LipModelStore(directory: fixture.directory, resources: fixture.resources) { _, destination in
            if await attempts.next() > 1 {
                try FileManager.default.copyItem(at: checkpoint, to: destination)
                return
            }
            try Data("partial".utf8).write(to: destination)
            started.fulfill()
            defer { drained.fulfill() }
            try await Task.sleep(nanoseconds: 60_000_000_000)
        }
        let pending = Task { try await store.install() }
        await fulfillment(of: [started], timeout: 2)
        let unrelated = fixture.directory.appendingPathComponent("unrelated")
        try Data("keep".utf8).write(to: unrelated)
        await store.cancelInstallation()
        await fulfillment(of: [drained], timeout: 2)
        do { _ = try await pending.value; XCTFail("Cancellation must reach the installer") }
        catch { XCTAssertTrue(error is CancellationError) }
        let installed = await store.isInstalled()
        XCTAssertFalse(installed)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: fixture.directory.path), ["unrelated"])
        XCTAssertEqual(try Data(contentsOf: unrelated), Data("keep".utf8))
        let retriedModel = try await store.install()
        XCTAssertEqual(try Data(contentsOf: retriedModel), Fixture.graph)
        let attemptCount = await attempts.value
        XCTAssertEqual(attemptCount, 2)
        XCTAssertEqual(try Data(contentsOf: unrelated), Data("keep".utf8))
    }

    private actor Counter {
        var value = 0
        func increment() { value += 1 }
        func next() -> Int { value += 1; return value }
    }

    private struct Fixture {
        static let graph = Data("tiny ONNX fixture".utf8)
        static let storage = Data("original raw tensor storage".utf8)
        let root: URL
        let resources: URL
        let directory: URL
        let checkpoint: URL

        init(destination: String = "storages/0.bin", entry: String = "archive/data/0", checkpointHash: String? = nil, storageHash: String? = nil) throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("LipModelStoreTests-\(UUID().uuidString)", isDirectory: true)
            resources = root.appendingPathComponent("resources", isDirectory: true)
            directory = root.appendingPathComponent("models", isDirectory: true)
            checkpoint = root.appendingPathComponent("checkpoint.zip")
            let archive = root.appendingPathComponent("archive/data", isDirectory: true)
            try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: archive, withIntermediateDirectories: true)
            try Self.graph.write(to: resources.appendingPathComponent("visual-ctc.onnx"))
            try Self.storage.write(to: archive.appendingPathComponent("0"))
            try Data("must never be evaluated".utf8).write(to: root.appendingPathComponent("archive/data.pkl"))
            let zip = Process()
            zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
            zip.arguments = ["-q", checkpoint.path, "archive/data/0", "archive/data.pkl"]
            zip.currentDirectoryURL = root
            try zip.run()
            zip.waitUntilExit()
            guard zip.terminationStatus == 0 else { throw LipModelStoreError.extractionFailed }
            let archiveData = try Data(contentsOf: checkpoint)
            let manifest: [String: Any] = [
                "format_version": 1,
                "checkpoint_url": "https://example.invalid/publisher-checkpoint.zip",
                "checkpoint_sha256": checkpointHash ?? Self.hash(archiveData),
                "checkpoint_bytes": archiveData.count,
                "graph_sha256": Self.hash(Self.graph), "graph_bytes": Self.graph.count,
                "source_revision": String(repeating: "a", count: 40),
                "storages": [destination: ["zip_entry": entry, "bytes": Self.storage.count, "sha256": storageHash ?? Self.hash(Self.storage)]]
            ]
            try JSONSerialization.data(withJSONObject: manifest, options: .sortedKeys).write(to: resources.appendingPathComponent("manifest.json"))
        }

        func store(downloads: Counter? = nil) -> LipModelStore {
            let checkpoint = checkpoint
            return LipModelStore(directory: directory, resources: resources) { _, destination in
                await downloads?.increment()
                try FileManager.default.copyItem(at: checkpoint, to: destination)
            }
        }

        func updateManifest(_ change: (inout [String: Any]) -> Void) throws {
            let url = resources.appendingPathComponent("manifest.json")
            var manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
            change(&manifest)
            try JSONSerialization.data(withJSONObject: manifest, options: .sortedKeys).write(to: url)
        }

        func cleanUp() { try? FileManager.default.removeItem(at: root) }

        private static func hash(_ data: Data) -> String {
            SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        }
    }
}
