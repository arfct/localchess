// LocalChessApp.swift — LocalChess
// Offline chess against the Arasan engine, running on the phone.

import SwiftUI

@main
struct LocalChessApp: App {
    @StateObject private var game = GameState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(game)
                .preferredColorScheme(.dark)
        }
    }
}
