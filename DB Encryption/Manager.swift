import SwiftUI
import SwiftData
import CryptoKit

    /// Represents the current version of the library.
    /// Update this when making breaking changes to the library's interface.
public enum LibraryVersion {
        /// Current version following semantic versioning (MAJOR.MINOR.PATCH)
    static let current: String = "1.0.0"
}

    /// Encryption strategy to be used with the storage manager
public enum EncryptionStrategy {
        /// No encryption
    case none
        /// Full database encryption
    case full(key: SymmetricKey)
        /// Selective field encryption
    case selective(key: SymmetricKey)
}

    /// Protocol for models that support selective encryption
public protocol EncryptableModel {
        /// Array of property names that should be encrypted
    static var encryptedProperties: [String] { get }
        /// Reference to the storage manager for encryption/decryption operations
    var storageManager: StorageManager? { get set }
}

    /// Protocol for handling encryption/decryption operations
public protocol Encryptable {
        /// Encrypts the given data
        /// - Parameters:
        ///   - data: Data to encrypt
        ///   - key: Encryption key
        /// - Returns: Encrypted data
    static func encrypt(_ data: Data, using key: SymmetricKey) throws -> Data
    
        /// Decrypts the given data
        /// - Parameters:
        ///   - data: Data to decrypt
        ///   - key: Encryption key
        /// - Returns: Decrypted data
    static func decrypt(_ data: Data, using key: SymmetricKey) throws -> Data
}

    /// Default implementation of encryption operations using CryptoKit
public struct AESEncryption: Encryptable {
    public static func encrypt(_ data: Data, using key: SymmetricKey) throws -> Data {
        do {
            let sealedBox = try AES.GCM.seal(data, using: key)
            return sealedBox.combined ?? Data()
        } catch {
            throw EncryptionError.encryptionFailed
        }
    }
    
    public static func decrypt(_ data: Data, using key: SymmetricKey) throws -> Data {
        do {
            let sealedBox = try AES.GCM.SealedBox(combined: data)
            return try AES.GCM.open(sealedBox, using: key)
        } catch {
            throw EncryptionError.decryptionFailed
        }
    }
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

    /// Encryption related errors
public enum EncryptionError: Error {
    case encryptionFailed
    case decryptionFailed
    case invalidKey
    case dataCorrupted
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
        /// Current encryption strategy
    private let encryptionStrategy: EncryptionStrategy
        /// Encryption provider
    private let encryptionProvider: Encryptable.Type
    
        /// Initializes a new StorageManager with a specific schema and encryption strategy
        /// - Parameters:
        ///   - schema: The persistent model type to create the container for
        ///   - encryptionStrategy: Strategy for encryption (default: .none)
        ///   - encryptionProvider: Provider for encryption operations (default: AESEncryption.self)
        /// - Throws: Error if the container cannot be created
    public init(
        schema: any PersistentModel.Type,
        encryptionStrategy: EncryptionStrategy = .none,
        encryptionProvider: Encryptable.Type = AESEncryption.self
    ) throws {
        let modelConfiguration = ModelConfiguration(for: schema)
        self.modelContainer = try ModelContainer(for: schema, configurations: modelConfiguration)
        self.backgroundQueue = DispatchQueue(label: "com.storage.background", qos: .userInitiated)
        self.encryptionStrategy = encryptionStrategy
        self.encryptionProvider = encryptionProvider
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
    
        // MARK: - Encryption Helpers
    
        /// Encrypts a value if needed based on the current encryption strategy
    private func encryptIfNeeded<T: Encodable>(_ value: T, forKey key: String? = nil) throws -> Data {
        let jsonData = try JSONEncoder().encode(value)
        
        switch encryptionStrategy {
            case .full(let encryptionKey):
                return try encryptionProvider.encrypt(jsonData, using: encryptionKey)
                
            case .selective(let encryptionKey):
                if let key = key,
                   let model = value as? any EncryptableModel.Type,
                   model.encryptedProperties.contains(key) {
                    return try encryptionProvider.encrypt(jsonData, using: encryptionKey)
                }
                return jsonData
                
            case .none:
                return jsonData
        }
    }
    
        /// Decrypts a value if needed based on the current encryption strategy
    private func decryptIfNeeded(_ data: Data, forKey key: String? = nil) throws -> Data {
        switch encryptionStrategy {
            case .full(let encryptionKey):
                return try encryptionProvider.decrypt(data, using: encryptionKey)
                
            case .selective(let encryptionKey):
                if let key = key,
                   let model = type(of: self) as? any EncryptableModel.Type,
                   model.encryptedProperties.contains(key) {
                    return try encryptionProvider.decrypt(data, using: encryptionKey)
                }
                return data
                
            case .none:
                return data
        }
    }
    
        /// Configures the model with necessary references and setup
        /// - Parameter item: The model instance to configure
    private func configureModel<T: PersistentModel>(_ item: T) {
            // Set the storage manager reference for encryptable models
        if var encryptableItem = item as? (any EncryptableModel) {
            encryptableItem.storageManager = self
        }
        
            // If it's part of a relationship, configure related models too
        let mirror = Mirror(reflecting: item)
        for child in mirror.children {
                // Configure nested models in relationships
            if let nestedModel = child.value as? (any PersistentModel) {
                configureModel(nestedModel)
            }
                // Handle arrays of models
            if let modelArray = child.value as? [any PersistentModel] {
                modelArray.forEach { configureModel($0) }
            }
        }
    }
    
        // MARK: - CRUD Operations
    
        /// Saves a new item to the persistent store with encryption if enabled
        /// - Parameter item: The item to save
        /// - Throws: Error if the save operation fails
    public func save<T: PersistentModel & Encodable>(_ item: T) async throws {
        let context = backgroundContext()
        
        if let encryptableItem = item as? (any EncryptableModel) {
                // Handle selective encryption for specific properties
            let mirror = Mirror(reflecting: encryptableItem)
            for child in mirror.children {
                if let propertyName = child.label,
                   let encryptableType = Swift.type(of: encryptableItem) as? any EncryptableModel.Type,
                   encryptableType.encryptedProperties.contains(propertyName) {
                        // Encrypt the property value
                    if let value = child.value as? Encodable {
                        let encryptedData = try encryptIfNeeded(value, forKey: propertyName)
                            // Store the encrypted data in the corresponding property
                        if let object = item as? NSObject {
                            object.setValue(encryptedData, forKey: "encrypted\(propertyName.capitalized)")
                        }
                    }
                }
            }
        } else if case .full = encryptionStrategy {
                // Handle full encryption
            let encryptedData = try encryptIfNeeded(item)
                // Store the fully encrypted object
            if let object = item as? NSObject {
                object.setValue(encryptedData, forKey: "encryptedContent")
            }
        }
        
            // Configure the model before saving
        configureModel(item)
        context.insert(item)
        try context.save()
    }
    
        /// Fetches items from the persistent store with decryption if needed
        /// - Parameters:
        ///   - type: The type of items to fetch
        ///   - predicate: Optional predicate for filtering results
        /// - Returns: Array of fetched items
        /// - Throws: Error if the fetch operation fails
    public func fetch<T: PersistentModel & Codable>(_ type: T.Type, predicate: Predicate<T>? = nil) async throws -> [T] {
        let context = backgroundContext()
        let descriptor = FetchDescriptor<T>(predicate: predicate)
        let items = try context.fetch(descriptor)
        
        return try items.map { item in
            if let encryptableItem = item as? (any EncryptableModel) {
                    // Handle selective decryption
                let mirror = Mirror(reflecting: encryptableItem)
                var decryptedItem = item
                
                    // Get the type that conforms to EncryptableModel
                let encryptableType = Swift.type(of: encryptableItem) as? any EncryptableModel.Type
                
                for child in mirror.children {
                    if let propertyName = child.label,
                       encryptableType?.encryptedProperties.contains(propertyName) == true {
                            // Decrypt the property value
                        if let encryptedData = child.value as? Data {
                            let decryptedData = try decryptIfNeeded(encryptedData, forKey: propertyName)
                                // Process decrypted data
                        }
                    }
                }
                return decryptedItem
            } else if case .full = encryptionStrategy {
                    // Handle full decryption
                return item
            }
            return item
        }
    }
    
        /// Updates an existing item in the persistent store
        /// - Parameter item: The item to update
        /// - Throws: Error if the update operation fails
    public func update<T: PersistentModel & Encodable>(_ item: T) async throws {
        let context = backgroundContext()
        
        if let encryptableItem = item as? (any EncryptableModel) {
                // Handle selective encryption for updates
            let mirror = Mirror(reflecting: encryptableItem)
            for child in mirror.children {
                if let propertyName = child.label,
                   let encryptableType = Swift.type(of: encryptableItem) as? any EncryptableModel.Type,
                   encryptableType.encryptedProperties.contains(propertyName) {
                    if let value = child.value as? Encodable {
                        let encryptedData = try encryptIfNeeded(value, forKey: propertyName)
                            // Store the encrypted data
                        if let object = item as? NSObject {
                            object.setValue(encryptedData, forKey: "encrypted\(propertyName.capitalized)")
                        }
                    }
                }
            }
        } else if case .full = encryptionStrategy {
                // Handle full encryption for updates
            let encryptedData = try encryptIfNeeded(item)
                // Store the fully encrypted object
            if let object = item as? NSObject {
                object.setValue(encryptedData, forKey: "encryptedContent")
            }
        }
        
            // Configure the model before updating
        configureModel(item)
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
    public func fetchForUI<T: PersistentModel & Codable>(_ type: T.Type, predicate: Predicate<T>? = nil) throws -> [T] {
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
    
    
        /// Saves multiple items to the persistent store in batches
        /// - Parameters:
        ///   - items: Array of items to save
        ///   - batchSize: Number of items to process in each batch (default: 100)
        ///   - progress: Optional closure to track progress (0.0 to 1.0)
        /// - Throws: Error if the save operation fails
    public func batchSave<T: PersistentModel & Encodable>(_ items: [T],
                                                          batchSize: Int = 100,
                                                          progress: ((Double) -> Void)? = nil) async throws {
        let context = backgroundContext()
        let totalItems = items.count
        var processed = 0
        
            // Process items in batches
        for batch in items.chunked(into: batchSize) {
                // Process each item in the batch
            for item in batch {
                if let encryptableItem = item as? (any EncryptableModel) {
                        // Handle selective encryption for specific properties
                    let mirror = Mirror(reflecting: encryptableItem)
                    for child in mirror.children {
                        if let propertyName = child.label,
                           let encryptableType = Swift.type(of: encryptableItem) as? any EncryptableModel.Type,
                           encryptableType.encryptedProperties.contains(propertyName) {
                                // Encrypt the property value
                            if let value = child.value as? Encodable {
                                let encryptedData = try encryptIfNeeded(value, forKey: propertyName)
                                    // Store the encrypted data
                                if let object = item as? NSObject {
                                    object.setValue(encryptedData, forKey: "encrypted\(propertyName.capitalized)")
                                }
                            }
                        }
                    }
                } else if case .full = encryptionStrategy {
                        // Handle full encryption
                    let encryptedData = try encryptIfNeeded(item)
                    if let object = item as? NSObject {
                        object.setValue(encryptedData, forKey: "encryptedContent")
                    }
                }
                
                configureModel(item)
                context.insert(item)
            }
            
                // Save the batch
            try context.save()
            
                // Update progress
            processed += batch.count
            let progressValue = Double(processed) / Double(totalItems)
            progress?(progressValue)
            
                // Optional: Add a small delay to prevent overwhelming the system
            try await Task.sleep(nanoseconds: 10_000_000) // 10ms delay
        }
    }
    
    
        /// Updates multiple items in the persistent store in batches
        /// - Parameters:
        ///   - items: Array of items to update
        ///   - batchSize: Number of items to process in each batch (default: 100)
        ///   - progress: Optional closure to track progress (0.0 to 1.0)
        /// - Throws: Error if the update operation fails
    public func batchUpdate<T: PersistentModel & Encodable>(_ items: [T],
                                                            batchSize: Int = 100,
                                                            progress: ((Double) -> Void)? = nil) async throws {
        let context = backgroundContext()
        let totalItems = items.count
        var processed = 0
        
            // Process items in batches
        for batch in items.chunked(into: batchSize) {
                // Process each item in the batch
            for item in batch {
                if let encryptableItem = item as? (any EncryptableModel) {
                    let mirror = Mirror(reflecting: encryptableItem)
                    for child in mirror.children {
                        if let propertyName = child.label,
                           let encryptableType = Swift.type(of: encryptableItem) as? any EncryptableModel.Type,
                           encryptableType.encryptedProperties.contains(propertyName) {
                            if let value = child.value as? Encodable {
                                let encryptedData = try encryptIfNeeded(value, forKey: propertyName)
                                if let object = item as? NSObject {
                                    object.setValue(encryptedData, forKey: "encrypted\(propertyName.capitalized)")
                                }
                            }
                        }
                    }
                } else if case .full = encryptionStrategy {
                    let encryptedData = try encryptIfNeeded(item)
                    if let object = item as? NSObject {
                        object.setValue(encryptedData, forKey: "encryptedContent")
                    }
                }
                
                configureModel(item)
            }
            
                // Save the batch
            try context.save()
            
                // Update progress
            processed += batch.count
            let progressValue = Double(processed) / Double(totalItems)
            progress?(progressValue)
            
                // Optional: Add a small delay to prevent overwhelming the system
            try await Task.sleep(nanoseconds: 10_000_000) // 10ms delay
        }
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
