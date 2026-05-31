import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthStore.self) private var authStore
    @Binding var selectedTabRaw: Int
    @State private var repository: Repository?

    var body: some View {
        Group {
            if authStore.isLoggedIn || authStore.isGuest {
                if let repo = repository {
                    RootTabView(selectedTabRaw: $selectedTabRaw)
                        .environment(repo)
                } else {
                    Color.bg
                        .ignoresSafeArea()
                        .onAppear {
                            repository = Repository(modelContext: modelContext)
                        }
                }
            } else {
                LoginView()
            }
        }
    }
}
