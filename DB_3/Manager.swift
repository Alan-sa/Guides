import SwiftUI
import SwiftData
import CryptoKit

    // MARK: - Versions & Enums
public enum LibraryVersion {
    static let current: String = "1.0.0"
}

public enum EncryptionStrategy {
    case none
    case encrypted(key: SymmetricKey)
}

public enum StorageError: Error {
    case migrationFailed
    case versionMismatch
    case modelNotFound
    case invalidSchema
    case contextError
    case encryptionError
}

    // MARK: - Protocol for constraining ID type
public protocol StorableIdentifiable: Identifiable where ID == String { }

    // MARK: - Encryption Implementation
private struct AESEncryption {
    static func encrypt(_ data: Data, using key: SymmetricKey) throws -> Data {
        do {
            let sealedBox = try AES.GCM.seal(data, using: key)
            return sealedBox.combined ?? Data()
        } catch {
            throw StorageError.encryptionError
        }
    }
    
    static func decrypt(_ data: Data, using key: SymmetricKey) throws -> Data {
        do {
            let sealedBox = try AES.GCM.SealedBox(combined: data)
            return try AES.GCM.open(sealedBox, using: key)
        } catch {
            throw StorageError.encryptionError
        }
    }
}

    // MARK: - Encrypted Container
@Model
final class EncryptedContainer {
    var id: String
    var encryptedData: Data
    var modelType: String
    
    init(id: String, encryptedData: Data, modelType: String) {
        self.id = id
        self.encryptedData = encryptedData
        self.modelType = modelType
    }
}

@available(iOS 17.0, *)
public actor StorageManager {
    private let modelContainer: ModelContainer
    private let backgroundQueue: DispatchQueue
    private let encryptionStrategy: EncryptionStrategy
    
    public init(encryptionStrategy: EncryptionStrategy = .none) throws {
        let schema = Schema([EncryptedContainer.self])
        let modelConfiguration = ModelConfiguration(schema: schema)
        self.modelContainer = try ModelContainer(for: schema, configurations: modelConfiguration)
        self.backgroundQueue = DispatchQueue(label: "com.storage.background", qos: .userInitiated)
        self.encryptionStrategy = encryptionStrategy
    }
    
        // MARK: - Context Management
    @MainActor private func mainContext() -> ModelContext {
        modelContainer.mainContext
    }
    
    private func backgroundContext() -> ModelContext {
        ModelContext(modelContainer)
    }
    
        // MARK: - Encryption Helpers
    private func encryptIfNeeded<T: Codable>(_ value: T) throws -> Data {
        let jsonData = try JSONEncoder().encode(value)
        
        switch encryptionStrategy {
            case .encrypted(let key):
                return try AESEncryption.encrypt(jsonData, using: key)
            case .none:
                return jsonData
        }
    }
    
    private func decryptIfNeeded(_ data: Data) throws -> Data {
        switch encryptionStrategy {
            case .encrypted(let key):
                return try AESEncryption.decrypt(data, using: key)
            case .none:
                return data
        }
    }
    
    private func getTypeName<T>(for type: T.Type) -> String {
        String(describing: type)
    }
    
        // MARK: - CRUD Operations
    public func save<T: Codable & StorableIdentifiable>(_ item: T) async throws {
        let context = backgroundContext()
        let encryptedData = try encryptIfNeeded(item)
        let typeName = getTypeName(for: T.self)
        
        let container = EncryptedContainer(
            id: item.id,
            encryptedData: encryptedData,
            modelType: typeName
        )
        context.insert(container)
        try context.save()
    }
    
    public func fetch<T: Codable>(_ type: T.Type, matching id: String) async throws -> T? {
        let context = backgroundContext()
        let typeName = getTypeName(for: T.self)
        
        let descriptor = FetchDescriptor<EncryptedContainer>(
            predicate: #Predicate<EncryptedContainer> { container in
                container.id == id && container.modelType == typeName
            }
        )
        
        guard let container = try context.fetch(descriptor).first else {
            return nil
        }
        
        let decryptedData = try decryptIfNeeded(container.encryptedData)
        return try JSONDecoder().decode(T.self, from: decryptedData)
    }
    
    public func fetchAll<T: Codable>(_ type: T.Type) async throws -> [T] {
        let context = backgroundContext()
        let typeName = getTypeName(for: T.self)
        
        let descriptor = FetchDescriptor<EncryptedContainer>(
            predicate: #Predicate<EncryptedContainer> { container in
                container.modelType == typeName
            }
        )
        
        let containers = try context.fetch(descriptor)
        
        return try containers.map { container in
            let decryptedData = try decryptIfNeeded(container.encryptedData)
            return try JSONDecoder().decode(T.self, from: decryptedData)
        }
    }
    
    public func update<T: Codable & StorableIdentifiable>(_ item: T) async throws {
        let context = backgroundContext()
        let typeName = getTypeName(for: T.self)
        
        let descriptor = FetchDescriptor<EncryptedContainer>(
            predicate: #Predicate<EncryptedContainer> { container in
                container.id == item.id && container.modelType == typeName
            }
        )
        
        guard let existingContainer = try context.fetch(descriptor).first else {
            throw StorageError.modelNotFound
        }
        
        let encryptedData = try encryptIfNeeded(item)
        existingContainer.encryptedData = encryptedData
        try context.save()
    }
    
    public func delete<T: Codable>(_ type: T.Type, id: String) async throws {
        let context = backgroundContext()
        let typeName = getTypeName(for: T.self)
        
        let descriptor = FetchDescriptor<EncryptedContainer>(
            predicate: #Predicate<EncryptedContainer> { container in
                container.id == id && container.modelType == typeName
            }
        )
        
        guard let container = try context.fetch(descriptor).first else {
            throw StorageError.modelNotFound
        }
        
        context.delete(container)
        try context.save()
    }
    
    public func deleteAll<T: Codable>(_ type: T.Type) async throws {
        let context = backgroundContext()
        let typeName = getTypeName(for: T.self)
        
        let descriptor = FetchDescriptor<EncryptedContainer>(
            predicate: #Predicate<EncryptedContainer> { container in
                container.modelType == typeName
            }
        )
        
        let containers = try context.fetch(descriptor)
        containers.forEach { context.delete($0) }
        try context.save()
    }
    
        // MARK: - Batch Operations
    public func batchSave<T: Codable & StorableIdentifiable>(_ items: [T],
                                                             batchSize: Int = 100,
                                                             progress: ((Double) -> Void)? = nil) async throws {
        let context = backgroundContext()
        let totalItems = items.count
        var processed = 0
        
        for batch in items.chunked(into: batchSize) {
            for item in batch {
                let encryptedData = try encryptIfNeeded(item)
                let typeName = getTypeName(for: T.self)
                let container = EncryptedContainer(
                    id: item.id,
                    encryptedData: encryptedData,
                    modelType: typeName
                )
                context.insert(container)
            }
            
            try context.save()
            
            processed += batch.count
            let progressValue = Double(processed) / Double(totalItems)
            progress?(progressValue)
            
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}

public extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
