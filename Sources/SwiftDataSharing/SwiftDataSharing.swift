import CoreData
import Dependencies
import Foundation
import OSLog
import Sharing
import SwiftData

let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "",
    category: "SwiftDataSharing"
)

func debug(_ operation: () -> Void) {
    if
        let isEnabledArgument = ProcessInfo.processInfo.environment["com.impossibleflight.SwiftDataSharing.debug"],
        let isEnabled = Bool(isEnabledArgument)
    {
        if isEnabled {
            operation()
        }
    }
}

func trace(_ operation: () -> Void) {
    if
        let isEnabledArgument = ProcessInfo.processInfo.environment["com.impossibleflight.SwiftDataSharing.trace"],
        let isEnabled = Bool(isEnabledArgument)
    {
        if isEnabled {
            operation()
        }
    }
}

@Model final class Empty {
    init() {}
}

enum DefaultModelContainerKey: DependencyKey {
    static var liveValue: ModelContainer {
        reportIssue(
      """
      A blank, in-memory persistent container is being used for the app.
      Override this dependency in the entry point of your app using `prepareDependencies`.
      """
        )
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try! ModelContainer(for: Empty.self, configurations: configuration)
    }
}

public extension DependencyValues {
    var modelContainer: ModelContainer {
        get { self[DefaultModelContainerKey.self] }
        set { self[DefaultModelContainerKey.self] = newValue }
    }
}

public extension SharedReaderKey {
    static func fetchFirst<Model>(
        _ fetchDescriptor: FetchDescriptor<Model>
    ) -> Self where Self == FetchFirstKey<Model>, Model: PersistentModel {
        FetchFirstKey(fetchDescriptor: fetchDescriptor)
    }

    static func fetchFirst<Model>(
        predicate: Predicate<Model>? = nil,
        sortBy: [SortDescriptor<Model>] = []
    ) -> Self where Self == FetchFirstKey<Model>, Model: PersistentModel {
        let descriptor = FetchDescriptor(predicate: predicate, sortBy: sortBy)
        return FetchFirstKey(fetchDescriptor: descriptor)
    }

    static func fetchAll<Model>(
        _ fetchDescriptor: FetchDescriptor<Model>
    ) -> Self where Self == FetchAllKey<Model>.Default, Model: PersistentModel {
        Self[FetchAllKey(fetchDescriptor: fetchDescriptor), default: []]
    }

    static func fetchAll<Model>(
        predicate: Predicate<Model>? = nil,
        sortBy: [SortDescriptor<Model>] = []
    ) -> Self where Self == FetchAllKey<Model>.Default, Model: PersistentModel {
        let descriptor = FetchDescriptor(predicate: predicate, sortBy: sortBy)
        return Self[FetchAllKey(fetchDescriptor: descriptor), default: []]
    }

    static func fetchedResults<Model>(
        _ fetchDescriptor: FetchDescriptor<Model>
    ) -> Self where Self == FetchedResultsKey<Model>, Model: PersistentModel {
        FetchedResultsKey(fetchDescriptor: fetchDescriptor)
    }

    static func fetchedResults<Model>(
        predicate: Predicate<Model>? = nil,
        sortBy: [SortDescriptor<Model>] = []
    ) -> Self where Self == FetchedResultsKey<Model>, Model: PersistentModel {
        let descriptor = FetchDescriptor(predicate: predicate, sortBy: sortBy)
        return FetchedResultsKey(fetchDescriptor: descriptor)
    }
}

public struct FetchFirstKey<Model: PersistentModel>: SharedReaderKey {
    public typealias FetchResult = Model?

    let fetchDescriptor: FetchDescriptor<Model>
    private let modelContainer: ModelContainer

    init(
        fetchDescriptor: FetchDescriptor<Model>
    ) {
        @Dependency(\.modelContainer) var modelContainer
        var descriptor = fetchDescriptor
        descriptor.fetchLimit = 1
        self.fetchDescriptor = descriptor
        self.modelContainer = modelContainer
    }

    public var id: String {
        "\(fetchDescriptor)"
    }

    public func load(
        context: LoadContext<FetchResult>,
        continuation: LoadContinuation<FetchResult>
    ) {
        debug { logger.debug("\(Self.self)(\(id)).\(#function)") }
        Task { @MainActor in
            do {
                let result = try modelContainer.mainContext.fetch(fetchDescriptor).first
                trace { logger.trace("FetchFirstKey.result: \(String(describing: result?.persistentModelID))") }
                continuation.resume(returning: result)
            } catch {
                logger.error("\(error)")
            }
        }
    }

    public func subscribe(
        context: LoadContext<FetchResult>,
        subscriber: SharedSubscriber<FetchResult>
    ) -> SharedSubscription {
        debug { logger.debug("\(Self.self)(\(id)).\(#function)") }
        let task = Task { @MainActor in
            // Send initial value
            do {
                subscriber.yield(try modelContainer.mainContext.fetch(fetchDescriptor).first)

                // Listen for changes
                let changeNotifications = NotificationCenter.default.notifications(named: .NSPersistentStoreRemoteChange)

                for try await _ in changeNotifications {
                    guard !Task.isCancelled else { break }
                    debug { logger.debug("FetchFirst(\(id)).NSPersistentStoreRemoteChange")}
                    let result = try modelContainer.mainContext.fetch(fetchDescriptor).first
                    trace { logger.trace("FetchFirstKey\(id)).fetchedResults: \(String(describing: result?.persistentModelID))") }
                    subscriber.yield(result)
                }
            } catch {
                logger.error("\(error)")
            }
        }

        return SharedSubscription {
            task.cancel()
        }
    }
}

public struct FetchAllKey<Model: PersistentModel>: SharedReaderKey {
    public typealias FetchResult = [Model]

    let fetchDescriptor: FetchDescriptor<Model>
    private let modelContainer: ModelContainer

    init(
        fetchDescriptor: FetchDescriptor<Model>,
    ) {
        @Dependency(\.modelContainer) var modelContainer
        self.fetchDescriptor = fetchDescriptor
        self.modelContainer = modelContainer
    }

    public var id: String {
        "\(fetchDescriptor)"
    }

    public func load(
        context: LoadContext<FetchResult>,
        continuation: LoadContinuation<FetchResult>
    ) {
        debug { logger.debug("\(Self.self)(\(id)).\(#function)") }
        Task { @MainActor in
            do {
                let results = try modelContainer.mainContext.fetch(fetchDescriptor)
                trace { logger.trace("FetchAllKey\(id)).result[id]: \(results.map { $0.persistentModelID })") }
                continuation.resume(returning: results)
            } catch {
                logger.error("\(error)")
            }
        }
    }

    public func subscribe(
        context: LoadContext<FetchResult>,
        subscriber: SharedSubscriber<FetchResult>
    ) -> SharedSubscription {
        debug { logger.debug("\(Self.self)(\(id)).\(#function)") }
        let task = Task { @MainActor in
            // Send initial results
            let initialResults = try modelContainer.mainContext.fetch(fetchDescriptor)
            trace { logger.trace("FetchAllKey\(id)).initialResults: \(initialResults.map { $0.persistentModelID })") }
            subscriber.yield(initialResults)

            // Listen for changes
            let changeNotifications = NotificationCenter.default.notifications(named: .NSPersistentStoreRemoteChange)

            for try await _ in changeNotifications {
                guard !Task.isCancelled else { break }
                debug { logger.debug("FetchAllKey\(id)).NSPersistentStoreRemoteChange")}
                let results = try modelContainer.mainContext.fetch(fetchDescriptor)
                trace { logger.trace("FetchAllKey\(id)).fetchedResults[id]: \(results.map { $0.persistentModelID })") }
                subscriber.yield(results)
            }
        }

        return SharedSubscription {
            task.cancel()
        }
    }
}

extension FetchResultsCollection: @retroactive @unchecked Sendable {}

public struct FetchedResultsKey<Model: PersistentModel>: SharedReaderKey {
    public typealias FetchResult = FetchResultsCollection<Model>?

    let fetchDescriptor: FetchDescriptor<Model>
    let batchSize: Int
    private let modelContainer: ModelContainer

    init(
        fetchDescriptor: FetchDescriptor<Model>,
        batchSize: Int = 20
    ) {
        @Dependency(\.modelContainer) var modelContainer
        self.fetchDescriptor = fetchDescriptor
        self.batchSize = batchSize
        self.modelContainer = modelContainer
    }

    public var id: String {
        "\(fetchDescriptor)"
    }

    public func load(
        context: LoadContext<FetchResult>,
        continuation: LoadContinuation<FetchResult>
    ) {
        debug { logger.debug("\(Self.self)(\(id)).\(#function)") }
        Task { @MainActor in
            let result = Result<FetchResult?, Error> {
                try modelContainer.mainContext.fetch(fetchDescriptor, batchSize: batchSize)
            }
            continuation.resume(with: result)
        }
    }

    public func subscribe(
        context: LoadContext<FetchResult>,
        subscriber: SharedSubscriber<FetchResult>
    ) -> SharedSubscription {
        debug { logger.debug("\(Self.self)(\(id)).\(#function)") }
        let task = Task { @MainActor in
            // Send initial results
            subscriber.yield(try modelContainer.mainContext.fetch(fetchDescriptor, batchSize: batchSize))

            // Listen for changes
            let changeNotifications = NotificationCenter.default.notifications(named: .NSPersistentStoreRemoteChange)

            for try await _ in changeNotifications {
                guard !Task.isCancelled else { break }
                let results = try modelContainer.mainContext.fetch(fetchDescriptor, batchSize: batchSize)
                subscriber.yield(results)
            }
        }

        return SharedSubscription {
            task.cancel()
        }
    }
}


