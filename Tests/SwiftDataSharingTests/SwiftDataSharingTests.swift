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
            @SharedReader(.fetchFirst(
                predicate: #Predicate<TestPerson> { $0.name == "Alice" }
            )) var person: TestPerson?
            
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
            )) var adults: [TestPerson]
            
            #expect(adults.isEmpty)
            
            let alice = TestPerson(name: "Alice", age: 25)
            let bob = TestPerson(name: "Bob", age: 30)
            let charlie = TestPerson(name: "Charlie", age: 20)
            
            modelContainer.mainContext.insert(alice)
            modelContainer.mainContext.insert(bob)
            modelContainer.mainContext.insert(charlie)
            try modelContainer.mainContext.save()
            
            try await Task.sleep(nanoseconds: 100_000_000)
            
            #expect(adults.count == 2)
            #expect(adults[0].name == "Alice")
            #expect(adults[1].name == "Bob")
            #expect(adults[0].age == 25)
            #expect(adults[1].age == 30)
            
            charlie.age = 35
            try modelContainer.mainContext.save()
            
            try await Task.sleep(nanoseconds: 100_000_000)
            
            #expect(adults.count == 3)
            #expect(adults[0].name == "Alice")
            #expect(adults[1].name == "Bob") 
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
    
    @Test func fetchedResults_reflectsDataChanges() async throws {
        try await withDependencies {
            $0.modelContainer = modelContainer
        } operation: {
            @SharedReader(.fetchedResults(
                sortBy: [SortDescriptor(\.name, order: .forward)]
            )) var allPeople: FetchResultsCollection<TestPerson>?
            
            #expect(allPeople == nil)

            let names = ["Alice", "Bob", "Charlie", "David", "Eve"]
            for (index, name) in names.enumerated() {
                let person = TestPerson(name: name, age: 20 + index)
                modelContainer.mainContext.insert(person)
            }
            try modelContainer.mainContext.save()
            
            try await Task.sleep(nanoseconds: 100_000_000)

            let fetchedResultPeople = try #require(allPeople)

            #expect(fetchedResultPeople.count == 5)
            let sortedNames = fetchedResultPeople.map(\.name)
            #expect(sortedNames == ["Alice", "Bob", "Charlie", "David", "Eve"])
            
            let frank = TestPerson(name: "Frank", age: 25)
            modelContainer.mainContext.insert(frank)
            try modelContainer.mainContext.save()
            
            try await Task.sleep(nanoseconds: 100_000_000)
            
            #expect(fetchedResultPeople.count == 6)
            let updatedNames = fetchedResultPeople.map(\.name)
            #expect(updatedNames.contains("Frank"))
            #expect(updatedNames == updatedNames.sorted())
        }
    }
    
    @Test func recordsIssue_whenMissingModelContainer() throws {
        withKnownIssue {
            @SharedReader(.fetchFirst(
                predicate: #Predicate<TestPerson> { $0.name == "Test" }
            )) var person: TestPerson?
        }
    }
}
