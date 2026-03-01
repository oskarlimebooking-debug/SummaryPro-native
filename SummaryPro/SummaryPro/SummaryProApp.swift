import SwiftUI
import AVFoundation

@main
struct SummaryProApp: App {
    @StateObject private var appViewModel = AppViewModel()
    @StateObject private var recordingViewModel = RecordingViewModel()
    @StateObject private var historyViewModel = HistoryViewModel()
    @StateObject private var historyStore = HistoryStore.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appViewModel)
                .environmentObject(recordingViewModel)
                .environmentObject(historyViewModel)
                .environmentObject(historyStore)
                .onAppear {
                    configureApp()
                }
        }
    }

    private func configureApp() {
        // Configure audio session
        recordingViewModel.audioRecorder.configureSession()

        // Wire up dependencies
        recordingViewModel.configure(appViewModel: appViewModel, historyStore: historyStore)
        historyViewModel.configure(historyStore: historyStore, appViewModel: appViewModel)
    }
}
