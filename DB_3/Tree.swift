//
//  Tree.swift
//  DB3
//
//  Created by Alan Santiago on 27/11/24.
//

    // Project Structure:
/*
 MyApp/
 ├── App/
 │   ├── MyAppApp.swift
 │   └── AppDelegate.swift
 ├── Features/
 │   └── Home/
 │       ├── Views/
 │       │   ├── HomeView.swift
 │       │   └── Components/
 │       │       └── WelcomeMessage.swift
 │       ├── ViewModels/
 │       │   └── HomeViewModel.swift
 │       └── Models/
 │           └── HomeModel.swift
 ├── Core/
 │   ├── Network/
 │   │   ├── NetworkManager.swift
 │   │   └── Endpoints.swift
 │   ├── Storage/
 │   │   └── LocalStorage.swift
 │   └── Extensions/
 │       └── View+Extensions.swift
 ├── Resources/
 │   ├── Assets.xcassets/
 │   ├── Localizable.strings
 │   └── Info.plist
 └── Utils/
 ├── Constants.swift
 └── Helpers/
 └── Logger.swift
 */

    // App/MyAppApp.swift
import SwiftUI

@main
struct MyAppApp: App {
    var body: some Scene {
        WindowGroup {
            HomeView()
        }
    }
}

    // Features/Home/Views/HomeView.swift
import SwiftUI

struct HomeView: View {
    @StateObject private var viewModel = HomeViewModel()
    
    var body: some View {
        VStack {
            WelcomeMessage(message: viewModel.welcomeMessage)
            
            Button("Update Message") {
                viewModel.updateMessage()
            }
            .padding()
        }
    }
}

    // Features/Home/Views/Components/WelcomeMessage.swift
import SwiftUI

struct WelcomeMessage: View {
    let message: String
    
    var body: some View {
        Text(message)
            .font(.title)
            .padding()
    }
}

    // Features/Home/ViewModels/HomeViewModel.swift
import Foundation
import Combine

class HomeViewModel: ObservableObject {
    @Published var welcomeMessage: String = "Hello, World!"
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        setupBindings()
    }
    
    private func setupBindings() {
            // Example of using Combine
        $welcomeMessage
            .dropFirst()
            .sink { [weak self] message in
                print("Message updated to: \(message)")
            }
            .store(in: &cancellables)
    }
    
    func updateMessage() {
        welcomeMessage = "Welcome to MVVM with SwiftUI!"
    }
}

    // Features/Home/Models/HomeModel.swift
struct HomeModel: Identifiable, Codable {
    let id: UUID
    let title: String
    let description: String
}

    // Core/Network/NetworkManager.swift
import Foundation
import Combine

protocol NetworkManaging {
    func fetch<T: Decodable>(_ endpoint: Endpoint) -> AnyPublisher<T, Error>
}

class NetworkManager: NetworkManaging {
    func fetch<T: Decodable>(_ endpoint: Endpoint) -> AnyPublisher<T, Error> {
            // Implementation
        fatalError("Implement network logic")
    }
}

    // Core/Network/Endpoints.swift
enum Endpoint {
    case home
    
    var path: String {
        switch self {
            case .home:
                return "/home"
        }
    }
}

    // Utils/Constants.swift
enum Constants {
    enum API {
        static let baseURL = "https://api.myapp.com"
    }
    
    enum Storage {
        static let userDefaultsKey = "com.myapp.userdefaults"
    }
}
