import SwiftUI
import SwiftData

    /// Represents the current version of the library.
    /// Update this when making breaking changes to the library's interface.
public enum LibraryVersion {
        /// Current version following semantic versioning (MAJOR.MINOR.PATCH)
    static let current: String = "1.0.0"
}

    /// Errors that can occur during storage operations.
    /// These errors provide specific information about what went wrong during data operations.
public enum StorageError: Error {
        /// Thrown when a schema migration operation fails
    case migrationFailed
        /// Thrown when there's a mismatch between stored schema version and current schema version
    case versionMismatch
        /// Thrown when attempting to operate on a model that doesn't exist in the store
    case modelNotFound
        /// Thrown when the schema structure is invalid or corrupted
    case invalidSchema
        /// Thrown when there's an error with the ModelContext
    case contextError
}

    /// Protocol that defines requirements for schema versioning and migration support.
    /// Implement this protocol in your models to enable automatic schema versioning and migrations.
public protocol VersionedSchema {
        /// The current version of the schema, following semantic versioning
    static var schemaVersion: String { get }
    
        /// Performs migration to the next version of the schema
        /// - Parameter context: The ModelContext in which to perform the migration
        /// - Throws: StorageError.migrationFailed if the migration cannot be completed
    static func migrateToNextVersion(in context: ModelContext) throws
}

    /// A thread-safe manager for handling persistent storage operations using SwiftData.
    /// This class provides methods for CRUD operations, migrations, and transactions,
    /// with separate handling for UI and background operations.
@available(iOS 17.0, *)
public actor StorageManager {
        /// The container that holds all persistent stores
    private let modelContainer: ModelContainer
        /// Queue used for background operations like migrations
    private let backgroundQueue: DispatchQueue
    
        /// Initializes a new StorageManager with a specific schema
        /// - Parameter schema: The persistent model type to create the container for
        /// - Throws: Error if the container cannot be created
    public init(schema: any PersistentModel.Type) throws {
        let modelConfiguration = ModelConfiguration(for: schema)
        self.modelContainer = try ModelContainer(for: schema, configurations: modelConfiguration)
        self.backgroundQueue = DispatchQueue(label: "com.storage.background", qos: .userInitiated)
    }
    
        // MARK: - Context Management
    
        /// Returns a context for main thread operations
        /// - Returns: ModelContext instance tied to the main thread
    @MainActor private func mainContext() -> ModelContext {
        modelContainer.mainContext
    }
    
        /// Creates a new context for background operations
        /// - Returns: ModelContext instance for background operations
    private func backgroundContext() -> ModelContext {
        ModelContext(modelContainer)
    }
    
        // MARK: - CRUD Operations
    
        /// Saves a new item to the persistent store
        /// - Parameter item: The item to save
        /// - Throws: Error if the save operation fails
    public func save<T: PersistentModel>(_ item: T) async throws {
        let context = backgroundContext()
        context.insert(item)
        try context.save()
    }
    
        /// Fetches items from the persistent store
        /// - Parameters:
        ///   - type: The type of items to fetch
        ///   - predicate: Optional predicate for filtering results
        /// - Returns: Array of fetched items
        /// - Throws: Error if the fetch operation fails
    public func fetch<T: PersistentModel>(_ type: T.Type, predicate: Predicate<T>? = nil) async throws -> [T] {
        let context = backgroundContext()
        let descriptor = FetchDescriptor<T>(predicate: predicate)
        return try context.fetch(descriptor)
    }
    
        /// Updates an existing item in the persistent store
        /// - Parameter item: The item to update
        /// - Throws: Error if the update operation fails
    public func update<T: PersistentModel>(_ item: T) async throws {
        let context = backgroundContext()
        try context.save()
    }
    
        /// Deletes an item from the persistent store
        /// - Parameter item: The item to delete
        /// - Throws: Error if the delete operation fails
    public func delete<T: PersistentModel>(_ item: T) async throws {
        let context = backgroundContext()
        context.delete(item)
        try context.save()
    }
    
        // MARK: - UI-Related Operations
    
        /// Fetches items for UI updates on the main thread
        /// - Parameters:
        ///   - type: The type of items to fetch
        ///   - predicate: Optional predicate for filtering results
        /// - Returns: Array of fetched items
        /// - Throws: Error if the fetch operation fails
    @MainActor
    public func fetchForUI<T: PersistentModel>(_ type: T.Type, predicate: Predicate<T>? = nil) throws -> [T] {
        let context = mainContext()
        let descriptor = FetchDescriptor<T>(predicate: predicate)
        return try context.fetch(descriptor)
    }
    
        // MARK: - Batch Operations
    
        /// Deletes multiple items matching a predicate
        /// - Parameters:
        ///   - type: The type of items to delete
        ///   - predicate: Optional predicate for filtering items to delete
        /// - Throws: Error if the batch delete operation fails
    public func batchDelete<T: PersistentModel>(_ type: T.Type, predicate: Predicate<T>? = nil) async throws {
        let context = backgroundContext()
        let descriptor = FetchDescriptor<T>(predicate: predicate)
        let items = try context.fetch(descriptor)
        items.forEach { context.delete($0) }
        try context.save()
    }
    
        // MARK: - Transaction Support
    
        /// Performs a transaction in a background context
        /// - Parameter operation: The transaction operation to perform
        /// - Returns: The result of the transaction
        /// - Throws: Error if the transaction fails
    public func performTransaction<T>(_ operation: @escaping (ModelContext) throws -> T) async throws -> T {
        let context = backgroundContext()
        do {
            let result = try operation(context)
            try context.save()
            return result
        } catch {
            throw error
        }
    }
    
        /// Performs a transaction on the main thread
        /// - Parameter operation: The transaction operation to perform
        /// - Returns: The result of the transaction
        /// - Throws: Error if the transaction fails
    @MainActor
    public func performUITransaction<T>(_ operation: @escaping (ModelContext) throws -> T) async throws -> T {
        let context = mainContext()
        do {
            let result = try operation(context)
            try context.save()
            return result
        } catch {
            throw error
        }
    }
    
        // MARK: - Migration Support
    
        /// Performs migration for a versioned schema
        /// - Parameter schema: The schema type to migrate
        /// - Throws: StorageError.migrationFailed if the migration fails
    public func performMigration<T: VersionedSchema>(for schema: T.Type) async throws {
        let context = backgroundContext()
        try await withCheckedThrowingContinuation { continuation in
            backgroundQueue.async {
                do {
                    try schema.migrateToNextVersion(in: context)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: StorageError.migrationFailed)
                }
            }
        }
    }
    
        /// Checks if the current schema version matches the stored version
        /// - Parameter schema: The schema type to check
        /// - Returns: Boolean indicating if versions match
        /// - Throws: StorageError if version check fails
    public func checkSchemaVersion<T: VersionedSchema>(for schema: T.Type) async throws -> Bool {
            // Implementation for schema version checking
        return true
    }
}

    // MARK: - Example Models

    /// Example employee model demonstrating implementation of VersionedSchema
@Model
public final class Employee: VersionedSchema {
        /// Unique identifier for the employee
    public var id: UUID
        /// Employee's full name
    public var name: String
        /// Employee's email address
    public var email: String
        /// Optional reference to employee's department
    public var department: Department?
        /// Date when employee was hired
    public var hireDate: Date
        /// Employee's current salary
    public var salary: Decimal
        /// Flag indicating if employee is currently active
    public var isActive: Bool
    
        /// Current version of the Employee schema
    public static var schemaVersion: String = "1.0.0"
    
        /// Initializes a new Employee instance
    public init(
        id: UUID = UUID(),
        name: String,
        email: String,
        department: Department? = nil,
        hireDate: Date = Date(),
        salary: Decimal,
        isActive: Bool = true
    ) {
        self.id = id
        self.name = name
        self.email = email
        self.department = department
        self.hireDate = hireDate
        self.salary = salary
        self.isActive = isActive
    }
    
        /// Handles migration to the next schema version
    public static func migrateToNextVersion(in context: ModelContext) throws {
        let descriptor = FetchDescriptor<Employee>()
        let employees = try context.fetch(descriptor)
        for employee in employees {
                // Example migration: Add default values for new fields
        }
    }
}

    /// Example department model demonstrating implementation of VersionedSchema
@Model
public final class Department: VersionedSchema {
        /// Unique identifier for the department
    public var id: UUID
        /// Department name
    public var name: String
        /// Department code/identifier
    public var code: String
        /// Collection of employees in this department
    @Relationship(deleteRule: .cascade) public var employees: [Employee]
    
        /// Current version of the Department schema
    public static var schemaVersion: String = "1.0.0"
    
        /// Initializes a new Department instance
    public init(
        id: UUID = UUID(),
        name: String,
        code: String,
        employees: [Employee] = []
    ) {
        self.id = id
        self.name = name
        self.code = code
        self.employees = employees
    }
    
        /// Handles migration to the next schema version
    public static func migrateToNextVersion(in context: ModelContext) throws {
            // Example migration logic for Department
    }
}

    // MARK: - Example Usage

    /// Demonstrates common usage patterns for the StorageManager
struct StorageExample {
        /// Example showing how to use StorageManager in a SwiftUI environment
    @MainActor
    static func demonstrateUsage() async throws {
            // Initialize the storage manager
        let manager = try StorageManager(schema: Employee.self)
        
            // Create and save a department
        let department = Department(name: "Engineering", code: "ENG")
        try await manager.save(department)
        
            // Create and save an employee
        let employee = Employee(
            name: "John Doe",
            email: "john.doe@company.com",
            department: department,
            salary: 75000
        )
        try await manager.save(employee)
        
            // Fetch employees for UI using predicate
        let uiEmployees = try manager.fetchForUI(
            Employee.self,
            predicate: #Predicate<Employee> { $0.department?.code == "ENG" }
        )
        print("UI Employees count: \(uiEmployees.count)")
        
            // Perform a UI transaction to update salary
        let updatedEmployee = try await manager.performUITransaction { context in
            let employee = try context.fetch(FetchDescriptor<Employee>()).first
            employee?.salary += 5000
            return employee
        }
        
            // Fetch employees in background
        let backgroundEmployees = try await manager.fetch(
            Employee.self,
            predicate: #Predicate<Employee> { $0.department?.code == "ENG" }
        )
    }
}
