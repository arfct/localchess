// LocalChessApp.swift — LocalChess
// Offline Duolingo-style chess vs a local GNU-Chess-style engine.

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
