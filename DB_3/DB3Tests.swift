//
//  DB3Tests.swift
//  DB3Tests
//
//  Created by Alan Santiago on 26/11/24.
//
import XCTest
import SwiftData
import CryptoKit
@testable import DB3 // Replace with your actual module name

    // MARK: - Test Model
struct TestUser: Codable, StorableIdentifiable {
    let id: String
    let name: String
    let email: String
}

final class StorageManagerTests: XCTestCase {
    var storageManager: StorageManager!
    var encryptedStorageManager: StorageManager!
    let testKey = SymmetricKey(size: .bits256)
    
    override func setUp() async throws {
        try await super.setUp()
        storageManager = try StorageManager(encryptionStrategy: .none)
        encryptedStorageManager = try StorageManager(encryptionStrategy: .encrypted(key: testKey))
    }
    
    override func tearDown() async throws {
        try await super.tearDown()
            // Clean up any test data
        try await storageManager.deleteAll(TestUser.self)
        try await encryptedStorageManager.deleteAll(TestUser.self)
        storageManager = nil
        encryptedStorageManager = nil
    }
    
        // MARK: - Helper Methods
    func createTestUser() -> TestUser {
        TestUser(id: UUID().uuidString, name: "Test User", email: "test@example.com")
    }
    
        // MARK: - Save Tests
    func testSaveUnencrypted() async throws {
        let user = createTestUser()
        try await storageManager.save(user)
        
        let fetchedUser = try await storageManager.fetch(TestUser.self, matching: user.id)
        XCTAssertNotNil(fetchedUser)
        XCTAssertEqual(fetchedUser?.id, user.id)
        XCTAssertEqual(fetchedUser?.name, user.name)
        XCTAssertEqual(fetchedUser?.email, user.email)
    }
    
    func testSaveEncrypted() async throws {
        let user = createTestUser()
        try await encryptedStorageManager.save(user)
        
        let fetchedUser = try await encryptedStorageManager.fetch(TestUser.self, matching: user.id)
        XCTAssertNotNil(fetchedUser)
        XCTAssertEqual(fetchedUser?.id, user.id)
        XCTAssertEqual(fetchedUser?.name, user.name)
        XCTAssertEqual(fetchedUser?.email, user.email)
    }
    
        // MARK: - Fetch Tests
    func testFetchNonExistentUser() async throws {
        let fetchedUser = try await storageManager.fetch(TestUser.self, matching: "non-existent-id")
        XCTAssertNil(fetchedUser)
    }
    
    func testFetchAll() async throws {
        let users = [
            TestUser(id: "1", name: "User 1", email: "user1@example.com"),
            TestUser(id: "2", name: "User 2", email: "user2@example.com"),
            TestUser(id: "3", name: "User 3", email: "user3@example.com")
        ]
        
        for user in users {
            try await storageManager.save(user)
        }
        
        let fetchedUsers = try await storageManager.fetchAll(TestUser.self)
        XCTAssertEqual(fetchedUsers.count, users.count)
        XCTAssertEqual(Set(fetchedUsers.map { $0.id }), Set(users.map { $0.id }))
    }
    
        // MARK: - Update Tests
    func testUpdate() async throws {
        let user = createTestUser()
        try await storageManager.save(user)
        
        let updatedUser = TestUser(id: user.id, name: "Updated Name", email: "updated@example.com")
        try await storageManager.update(updatedUser)
        
        let fetchedUser = try await storageManager.fetch(TestUser.self, matching: user.id)
        XCTAssertEqual(fetchedUser?.name, "Updated Name")
        XCTAssertEqual(fetchedUser?.email, "updated@example.com")
    }
    
    func testUpdateNonExistentUser() async throws {
        let user = createTestUser()
        do {
            try await storageManager.update(user)
            XCTFail("Expected error when updating non-existent user")
        } catch StorageError.modelNotFound {
                // Expected error
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
        // MARK: - Delete Tests
    func testDelete() async throws {
        let user = createTestUser()
        try await storageManager.save(user)
        
        try await storageManager.delete(TestUser.self, id: user.id)
        
        let fetchedUser = try await storageManager.fetch(TestUser.self, matching: user.id)
        XCTAssertNil(fetchedUser)
    }
    
    func testDeleteNonExistentUser() async throws {
        do {
            try await storageManager.delete(TestUser.self, id: "non-existent-id")
            XCTFail("Expected error when deleting non-existent user")
        } catch StorageError.modelNotFound {
                // Expected error
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
        // MARK: - Batch Operation Tests
    func testBatchSave() async throws {
        let users = (1...100).map { i in
            TestUser(id: "\(i)", name: "User \(i)", email: "user\(i)@example.com")
        }
        
        var progressUpdates: [Double] = []
        try await storageManager.batchSave(users, batchSize: 10) { progress in
            progressUpdates.append(progress)
        }
        
        let fetchedUsers = try await storageManager.fetchAll(TestUser.self)
        XCTAssertEqual(fetchedUsers.count, users.count)
        
            // Verify progress updates
        XCTAssertTrue(progressUpdates.contains(1.0)) // Should have reached 100%
        XCTAssertEqual(progressUpdates.sorted(), progressUpdates) // Should be monotonically increasing
    }
    
        // MARK: - Error Handling Tests
    func testEncryptionWithWrongKey() async throws {
        let user = createTestUser()
        try await encryptedStorageManager.save(user)
        
            // Create new storage manager with different key
        let wrongKey = SymmetricKey(size: .bits256)
        let wrongKeyManager = try StorageManager(encryptionStrategy: .encrypted(key: wrongKey))
        
        do {
            _ = try await wrongKeyManager.fetch(TestUser.self, matching: user.id)
            XCTFail("Expected decryption to fail with wrong key")
        } catch {
                // Expected error
            XCTAssertTrue(true)
        }
    }
    
        // MARK: - Performance Tests
    func testBatchSavePerformance() throws {
        let users = (1...1000).map { i in
            TestUser(id: "\(i)", name: "User \(i)", email: "user\(i)@example.com")
        }
        
        measure {
            let expectation = expectation(description: "Batch save completion")
            
            Task {
                do {
                    try await storageManager.batchSave(users, batchSize: 100)
                    expectation.fulfill()
                } catch {
                    XCTFail("Batch save failed: \(error)")
                }
            }
            
            wait(for: [expectation], timeout: 30.0)
        }
    }
}
