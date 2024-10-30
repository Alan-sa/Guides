//
//  ContentView.swift
//  ThreadsStorageDB
//
//  Created by Alan Santiago on 28/10/24.
//

import SwiftUI

struct EmployeeListView: View {
    let manager: StorageManager
    @State private var employees: [Employee] = []
    @State private var error: Error?
    
    var body: some View {
        List(employees, id: \.id) { employee in
            Text(employee.name)
        }
        .task {
            do {
                    // Fetch employees for UI
                employees = try manager.fetchForUI(Employee.self)
            } catch {
                self.error = error
            }
        }
    }
}

struct EmployeeManager {
    let manager: StorageManager
    
    func addEmployee(_ employee: Employee) async throws {
            // Background operation
        try await manager.save(employee)
        
            // Update UI on main actor
        @MainActor func updateUI() throws {
                // Fetch updated list
            let updatedEmployees = try manager.fetchForUI(Employee.self)
                // Update your UI state here
        }
        
            // Call the main actor function
        try await updateUI()
    }
}
