import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Binding var selectedTabRaw: Int
    @State private var repository: Repository?

    var body: some View {
        if let repo = repository {
            RootTabView(selectedTabRaw: $selectedTabRaw)
                .environment(repo)
        } else {
            ZStack {
                Color.bg
                ProgressView()
            }
            .ignoresSafeArea()
            .task {
                // Async on MainActor — does not block view render cycle
                repository = Repository(modelContext: modelContext)
            }
        }
    }
}
