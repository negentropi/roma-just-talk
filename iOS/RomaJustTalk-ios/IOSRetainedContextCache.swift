import Foundation

actor IOSRetainedContextCache<Context: Sendable> {
    typealias Factory = @Sendable (String) async throws -> Context
    typealias Release = @Sendable (Context) async -> Void

    private struct Retained: Sendable {
        let modelPath: String
        let context: Context
    }

    private struct Loading: Sendable {
        let id: UUID
        let modelPath: String
        let task: Task<Context, Error>
    }

    private let factory: Factory
    private let release: Release
    private var retained: Retained?
    private var loading: Loading?

    init(factory: @escaping Factory, release: @escaping Release) {
        self.factory = factory
        self.release = release
    }

    func context(forModelPath modelPath: String) async throws -> Context {
        if let retained, retained.modelPath == modelPath {
            return retained.context
        }
        if let loading, loading.modelPath == modelPath {
            return try await loading.task.value
        }

        await discardCurrentContext()

        let id = UUID()
        let task = Task { try await factory(modelPath) }
        loading = Loading(id: id, modelPath: modelPath, task: task)

        do {
            let context = try await task.value
            guard loading?.id == id else {
                await release(context)
                throw CancellationError()
            }
            loading = nil
            retained = Retained(modelPath: modelPath, context: context)
            return context
        } catch {
            if loading?.id == id {
                loading = nil
            }
            throw error
        }
    }

    func releaseRetainedContext() async {
        await discardCurrentContext()
    }

    func retainedModelPath() -> String? {
        retained?.modelPath
    }

    private func discardCurrentContext() async {
        loading?.task.cancel()
        loading = nil

        guard let retained else { return }
        self.retained = nil
        await release(retained.context)
    }
}
