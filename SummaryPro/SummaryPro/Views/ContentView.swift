import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appViewModel: AppViewModel
    @EnvironmentObject var recordingViewModel: RecordingViewModel
    @EnvironmentObject var historyViewModel: HistoryViewModel
    @EnvironmentObject var historyStore: HistoryStore

    @State private var selectedTab = 0

    var body: some View {
        Group {
            if !appViewModel.isSetupComplete || appViewModel.showSetup {
                SetupView()
            } else {
                mainContent
            }
        }
        .task {
            if appViewModel.isSetupComplete {
                await appViewModel.fetchModels()
            }
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        switch recordingViewModel.state {
        case .processing:
            ProcessingView()
        case .results:
            ResultsView()
        default:
            TabView(selection: $selectedTab) {
                RecordingView()
                    .tabItem {
                        Image(systemName: "mic.fill")
                        Text("Snemanje")
                    }
                    .tag(0)

                HistoryListView()
                    .tabItem {
                        Image(systemName: "clock.fill")
                        Text("Zgodovina")
                    }
                    .tag(1)
            }
            .tint(Color(red: 0.102, green: 0.451, blue: 0.910)) // #1a73e8
        }
    }
}
