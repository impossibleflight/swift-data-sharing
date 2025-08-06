import CoreData
import Dependencies
import Foundation
import OSLog
import Sharing
import SwiftData

public protocol ModelConvertible<Model>: Sendable {
    associatedtype Model: PersistentModel
    init(_ model: Model)
}

public extension SharedReaderKey {
    static func fetchFirst<Convertible, Model>(
        _ fetchDescriptor: FetchDescriptor<Model>
    ) -> Self
    where
        Self == FetchFirstKey<Convertible>,
        Convertible: ModelConvertible,
        Model == Convertible.Model
    {
        FetchFirstKey(fetchDescriptor: fetchDescriptor)
    }

    static func fetchFirst<Convertible, Model>(
        predicate: Predicate<Model>? = nil,
        sortBy: [SortDescriptor<Model>] = []
    ) -> Self
    where
        Self == FetchFirstKey<Convertible>,
        Convertible: ModelConvertible,
        Model == Convertible.Model
    {
        let descriptor = FetchDescriptor(predicate: predicate, sortBy: sortBy)
        return FetchFirstKey(fetchDescriptor: descriptor)
    }

    static func fetchAll<Convertible, Model>(
        _ fetchDescriptor: FetchDescriptor<Model>
    ) -> Self
    where
    Self == FetchAllKey<Convertible>.Default,
        Convertible: ModelConvertible,
        Model == Convertible.Model
    {
        Self[FetchAllKey(fetchDescriptor: fetchDescriptor), default: []]
    }

    static func fetchAll<Convertible, Model>(
        predicate: Predicate<Model>? = nil,
        sortBy: [SortDescriptor<Model>] = []
    ) -> Self where
    Self == FetchAllKey<Convertible>.Default,
        Convertible: ModelConvertible,
        Model == Convertible.Model
    {
        let descriptor = FetchDescriptor(predicate: predicate, sortBy: sortBy)
        return Self[FetchAllKey(fetchDescriptor: descriptor), default: []]
    }
}

public struct FetchFirstKey<Value: ModelConvertible>: SharedReaderKey {
    public typealias Model = Value.Model
    public typealias FetchResult = Value?

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
                if let result = try modelContainer.mainContext.fetch(fetchDescriptor).first {
                    trace { logger.trace("\(Self.self).result: \(String(describing: result.persistentModelID))") }
                    continuation.resume(returning: .init(result))
                }
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
                if let initial = try modelContainer.mainContext.fetch(fetchDescriptor).first {
                    subscriber.yield(.init(initial))
                } else {
                    subscriber.yield(nil)
                }

                // Listen for changes
                let changeNotifications = NotificationCenter.default.notifications(named: .NSPersistentStoreRemoteChange)

                for try await _ in changeNotifications {
                    guard !Task.isCancelled else { break }
                    debug { logger.debug("\(Self.self)(\(id)).NSPersistentStoreRemoteChange")}
                    if let result = try modelContainer.mainContext.fetch(fetchDescriptor).first {
                        trace { logger.trace("\(Self.self)\(id)).fetchedResults: \(String(describing: result.persistentModelID))") }
                        subscriber.yield(.init(result))
                    } else {
                        subscriber.yield(nil)

                    }
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

public struct FetchAllKey<Value: ModelConvertible>: SharedReaderKey {
    public typealias Model = Value.Model
    public typealias FetchResult = [Value]

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
                let initialResults = try modelContainer.mainContext.fetch(fetchDescriptor)
                trace { logger.trace("\(Self.self)\(id)).result[id]: \(initialResults.map { $0.persistentModelID })") }
                let values = initialResults.map { Value.init($0) }
                continuation.resume(returning: values)
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
            trace { logger.trace("\(Self.self)(\(id)).initialResults: \(initialResults.map { $0.persistentModelID })") }
            let values = initialResults.map { Value.init($0) }
            subscriber.yield(values)

            // Listen for changes
            let changeNotifications = NotificationCenter.default.notifications(named: .NSPersistentStoreRemoteChange)

            for try await _ in changeNotifications {
                guard !Task.isCancelled else { break }
                debug { logger.debug("\(Self.self)(\(id)).NSPersistentStoreRemoteChange")}
                let results = try modelContainer.mainContext.fetch(fetchDescriptor)
                trace { logger.trace("\(Self.self)(\(id)).fetchedResults[id]: \(results.map { $0.persistentModelID })") }
                let values = results.map { Value.init($0) }
                subscriber.yield(values)
            }
        }

        return SharedSubscription {
            task.cancel()
        }
    }
}


