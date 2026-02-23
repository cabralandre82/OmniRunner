import SwiftUI

@main
struct OmniRunnerWatchApp: App {
    @StateObject private var workoutManager = WatchWorkoutManager()
    @StateObject private var connectivityManager = WatchConnectivityManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(workoutManager)
                .environmentObject(connectivityManager)
                .onAppear {
                    workoutManager.connectivity = connectivityManager
                }
        }
    }
}
