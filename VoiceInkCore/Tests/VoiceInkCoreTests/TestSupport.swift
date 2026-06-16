import Foundation

class XCTestCase {}

enum VoiceInkCoreTestRecorder {
    private static let lock = NSLock()
    private static var failures: [String] = []

    static var failureCount: Int {
        lock.withLock {
            failures.count
        }
    }

    static var failureSummary: String {
        lock.withLock {
            failures.joined(separator: "\n")
        }
    }

    static func record(_ message: String, file: StaticString = #filePath, line: UInt = #line) {
        lock.withLock {
            failures.append("\(file):\(line): \(message)")
        }
    }
}

struct VoiceInkCoreTestUnwrapError: Error, CustomStringConvertible {
    let description: String
}

func XCTFail(_ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    VoiceInkCoreTestRecorder.record(message.isEmpty ? "failed" : message, file: file, line: line)
}

func XCTAssertTrue(
    _ expression: @autoclosure () throws -> Bool,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) {
    do {
        guard try expression() else {
            let message = message()
            VoiceInkCoreTestRecorder.record(message.isEmpty ? "expected true" : message, file: file, line: line)
            return
        }
    } catch {
        let message = message()
        let defaultMessage = "unexpected thrown error: \(error)"
        VoiceInkCoreTestRecorder.record(message.isEmpty ? defaultMessage : message, file: file, line: line)
    }
}

func XCTAssertFalse(
    _ expression: @autoclosure () throws -> Bool,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) {
    do {
        guard try !expression() else {
            let message = message()
            VoiceInkCoreTestRecorder.record(message.isEmpty ? "expected false" : message, file: file, line: line)
            return
        }
    } catch {
        let message = message()
        let defaultMessage = "unexpected thrown error: \(error)"
        VoiceInkCoreTestRecorder.record(message.isEmpty ? defaultMessage : message, file: file, line: line)
    }
}

func XCTAssertNil<T>(
    _ expression: @autoclosure () throws -> T?,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) {
    do {
        guard try expression() == nil else {
            let message = message()
            VoiceInkCoreTestRecorder.record(message.isEmpty ? "expected nil" : message, file: file, line: line)
            return
        }
    } catch {
        let message = message()
        let defaultMessage = "unexpected thrown error: \(error)"
        VoiceInkCoreTestRecorder.record(message.isEmpty ? defaultMessage : message, file: file, line: line)
    }
}

func XCTAssertEqual<T: Equatable>(
    _ expression1: @autoclosure () throws -> T,
    _ expression2: @autoclosure () throws -> T,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) {
    do {
        let left = try expression1()
        let right = try expression2()
        guard left == right else {
            let message = message()
            let defaultMessage = "expected \(String(describing: left)) to equal \(String(describing: right))"
            VoiceInkCoreTestRecorder.record(message.isEmpty ? defaultMessage : message, file: file, line: line)
            return
        }
    } catch {
        let message = message()
        let defaultMessage = "unexpected thrown error: \(error)"
        VoiceInkCoreTestRecorder.record(message.isEmpty ? defaultMessage : message, file: file, line: line)
    }
}

func XCTAssertEqual(
    _ expression1: @autoclosure () throws -> Float,
    _ expression2: @autoclosure () throws -> Float,
    accuracy: Float,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) {
    do {
        let left = try expression1()
        let right = try expression2()
        guard abs(left - right) <= accuracy else {
            let message = message()
            let defaultMessage = "expected \(left) to equal \(right) +/- \(accuracy)"
            VoiceInkCoreTestRecorder.record(message.isEmpty ? defaultMessage : message, file: file, line: line)
            return
        }
    } catch {
        let message = message()
        let defaultMessage = "unexpected thrown error: \(error)"
        VoiceInkCoreTestRecorder.record(message.isEmpty ? defaultMessage : message, file: file, line: line)
    }
}

func XCTAssertEqual(
    _ expression1: @autoclosure () throws -> Double,
    _ expression2: @autoclosure () throws -> Double,
    accuracy: Double,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) {
    do {
        let left = try expression1()
        let right = try expression2()
        guard abs(left - right) <= accuracy else {
            let message = message()
            let defaultMessage = "expected \(left) to equal \(right) +/- \(accuracy)"
            VoiceInkCoreTestRecorder.record(message.isEmpty ? defaultMessage : message, file: file, line: line)
            return
        }
    } catch {
        let message = message()
        let defaultMessage = "unexpected thrown error: \(error)"
        VoiceInkCoreTestRecorder.record(message.isEmpty ? defaultMessage : message, file: file, line: line)
    }
}

func XCTAssertLessThan<T: Comparable>(
    _ expression1: @autoclosure () throws -> T,
    _ expression2: @autoclosure () throws -> T,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) {
    do {
        let left = try expression1()
        let right = try expression2()
        guard left < right else {
            let message = message()
            let defaultMessage = "expected \(String(describing: left)) to be less than \(String(describing: right))"
            VoiceInkCoreTestRecorder.record(message.isEmpty ? defaultMessage : message, file: file, line: line)
            return
        }
    } catch {
        let message = message()
        let defaultMessage = "unexpected thrown error: \(error)"
        VoiceInkCoreTestRecorder.record(message.isEmpty ? defaultMessage : message, file: file, line: line)
    }
}

func XCTUnwrap<T>(
    _ expression: @autoclosure () throws -> T?,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> T {
    guard let value = try expression() else {
        let message = message()
        let description = message.isEmpty ? "expected non-nil value" : message
        VoiceInkCoreTestRecorder.record(description, file: file, line: line)
        throw VoiceInkCoreTestUnwrapError(description: description)
    }
    return value
}
