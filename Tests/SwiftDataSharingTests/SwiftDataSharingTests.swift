import Dependencies
import Foundation
import Sharing
import SwiftData
import Testing
@testable import SwiftDataSharing

@Model
final class TestPerson {
    var name: String = ""
    var age: Int = 0
    
    init(name: String = "", age: Int = 0) {
        self.name = name
        self.age = age
    }
}

struct PersonValue: ModelConvertible {
    var name: String
    var age: Int
    
    init(_ model: TestPerson) {
        self.init(name: model.name, age: model.age)
    }

    init(name: String, age: Int) {
        self.age = age
        self.name = name
    }
}

extension TestPerson: Equatable {
    static func == (lhs: TestPerson, rhs: TestPerson) -> Bool {
        return lhs.persistentModelID == rhs.persistentModelID
    }
}

@MainActor
struct SwiftDataSharingTests {
    let modelContainer: ModelContainer
    
    init() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        modelContainer = try ModelContainer(for: TestPerson.self, configurations: config)
    }

    @Test func fetchFirst_reflectsDataChanges() async throws {
        try await withDependencies {
            $0.modelContainer = modelContainer
        } operation: {
        let key = FetchFirstKey<PersonValue>.fetchFirst(
            predicate: #Predicate<TestPerson> { $0.name == "Alice" }
        )
            @SharedReader(key) var person: PersonValue?

            #expect(person == nil)
            
            let alice = TestPerson(name: "Alice", age: 25)
            modelContainer.mainContext.insert(alice)
            try modelContainer.mainContext.save()
            
            try await Task.sleep(nanoseconds: 100_000_000)
            
            #expect(person != nil)
            #expect(person?.name == "Alice")
            #expect(person?.age == 25)
            
            alice.age = 30
            try modelContainer.mainContext.save()
            
            try await Task.sleep(nanoseconds: 100_000_000)
            
            #expect(person?.age == 30)
            
            modelContainer.mainContext.delete(alice)
            try modelContainer.mainContext.save()
            
            try await Task.sleep(nanoseconds: 100_000_000)
            
            #expect(person == nil)
        }
    }

    @Test func fetchAll_reflectsDataChanges() async throws {
        try await withDependencies {
            $0.modelContainer = modelContainer
        } operation: {
            @SharedReader(.fetchAll(
                predicate: #Predicate<TestPerson> { $0.age >= 25 },
                sortBy: [SortDescriptor(\.age, order: .forward)]
            )) var adults: [PersonValue]

            #expect(adults.isEmpty)
            
            let alice = TestPerson(name: "Alice", age: 25)
            let bob = TestPerson(name: "Bob", age: 30)
            let charlie = TestPerson(name: "Charlie", age: 20)

            try modelContainer.mainContext.transaction {
                modelContainer.mainContext.insert(alice)
                modelContainer.mainContext.insert(bob)
                modelContainer.mainContext.insert(charlie)
            }

            try await Task.sleep(nanoseconds: 100_000_000)
            
            #expect(adults.count == 2)
            #expect(adults[0].name == "Alice")
            #expect(adults[1].name == "Bob")

            charlie.age = 35
            try modelContainer.mainContext.save()
            
            try await Task.sleep(nanoseconds: 100_000_000)
            
            #expect(adults.count == 3)
            #expect(adults[2].name == "Charlie")
            #expect(adults[2].age == 35)
            
            modelContainer.mainContext.delete(bob)
            try modelContainer.mainContext.save()
            
            try await Task.sleep(nanoseconds: 100_000_000)
            
            #expect(adults.count == 2)
            #expect(adults[0].name == "Alice")
            #expect(adults[1].name == "Charlie")
        }
    }

    @Test func recordsIssue_whenMissingModelContainer() {
        withKnownIssue {
            @SharedReader(.fetchFirst(
                predicate: #Predicate<TestPerson> { $0.name == "Test" }
            )) var person: PersonValue?
        }
    }
}
